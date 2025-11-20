# How-to: Idempotent CRUD

`IdempotentCrudService` (`src/Services/IdempotentCrudService.php`) wraps every CRUD action in an idempotency guard so retries (network, queue replays, user double-submit) do not duplicate work. It relies on an `IdempotencyStore` implementation – the repo ships with `PdoIdempotencyStore` and `InMemoryIdempotencyStore`.

## 1. Table schema

```sql
CREATE TABLE IF NOT EXISTS bc_idempotency (
    id_key      VARCHAR(191) PRIMARY KEY,
    status      VARCHAR(32) NOT NULL,            -- 'in_progress'|'success'|'failed'
    result_json JSON NULL,                       -- PG uses jsonb
    created_at  TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at  TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
);
CREATE INDEX IF NOT EXISTS idx_bc_idem_updated ON bc_idempotency(updated_at);
```

Use `utf8mb4`/`pg_catalog` encodings and tune the column lengths if you need larger keys.

## 2. Wiring the service

```php
use BlackCat\Database\Services\IdempotentCrudService;
use BlackCat\Database\Idempotency\PdoIdempotencyStore;

$store = new PdoIdempotencyStore($db);
$service = new IdempotentCrudService($db, $repository, $cache, $dispatcher, $outbox, $store);
```

- `$repository` is the generated `ContractRepository`.
- `$cache`, `$dispatcher`, `$outbox` are optional (pass `null` if unused).
- The constructor accepts `defaultTtlSec` (defaults to 3600) and `defaultWaitMs` (2 seconds) to control how long successful payloads live and how long callers wait when another worker is currently processing the same key.

## 3. Guarding an action

```php
$paymentKey = sprintf('order:%d:charge:%s', $orderId, $payload['idempotency_token']);

$result = $service->withIdempotency($paymentKey, function () use ($service, $orderId, $payload) {
    return $service->update($orderId, ['status' => 'paid']);
});
```

- `withIdempotency()` trims/validates the key, attempts to `begin()` the record, and either runs the callback (owner) or waits up to `$defaultWaitMs` for another process to finish.
- Return values are stored as arrays. Scalars are wrapped as `['value' => $result]` so future calls can unwrap them consistently.
- If the previous attempt stored `STATUS_FAILED`, new calls throw immediately with the stored reason. Mark user-facing errors carefully so replays remain safe.

## 4. Convenience wrappers

The service exposes typed helpers that wrap the same logic:

```php
$dto = $service->createIdempotent($rowPayload, $idempotencyKey);
$service->updateIdempotent($id, $payload, $key);
$service->deleteIdempotent($id, $key);
$service->upsertIdempotent($row, $key);
```

They prefix the key with the operation name (`create:`, `update:`, etc.) and forward to `withIdempotency()`.

## 5. Purging old keys

`PdoIdempotencyStore::purgeOlderThan(DateInterval $age)` deletes stale rows based on `updated_at`. Run it from a scheduled job (daily/weekly) to keep the table bounded.

```php
$store->purgeOlderThan(new DateInterval('P30D')); // keep 30 days
```

## 6. Operational tips

- When the store is unreachable, the service logs a warning via `Telemetry` and executes the action anyway (best effort). Keep an eye on logs/metrics if idempotency is business critical.
- Use stable, user-provided keys (request UUID, payment intent ID, etc.). If you hash user input, include the environment/cluster name so keys do not collide across deployments.
- Mark sensitive parameters (`#[\SensitiveParameter]`) when you forward user-provided data into callbacks to keep stack traces and logs clean.
