# How-to: Audit trail

`AuditTrail` (`src/Audit/AuditTrail.php`) captures row-level mutations and transaction metadata with JSON payloads and observability fields. Use it whenever regulatory or debugging requirements demand a full history.

## 1. Install the audit tables

```php
use BlackCat\Database\Audit\AuditTrail;

$audit = new AuditTrail($db, tblChanges: 'changes', tblTx: 'audit_tx');
$audit->installSchema(); // idempotent
```

The helper creates:

- `changes` – columns: `id`, `ts`, `table_name`, `pk`, `op`, `actor`, `before_data`, `after_data`.
- `audit_tx` – columns: `id`, `at`, `phase`, `corr`, `tx`, `svc`, `op`, `actor`, `ms`.

PostgreSQL uses `jsonb` and `timestamptz(6)`, MySQL/MariaDB use `JSON` (or LONGTEXT when JSON is aliased) plus microsecond `TIMESTAMP(6)`.

## 2. Record change events

```php
$audit->record(
    table: 'orders',
    pk: 123,
    op: 'update',
    before: ['status' => 'pending', 'total' => 100],
    after:  ['status' => 'paid', 'total' => 100],
    actor: $userId,
    meta: [
        'corr' => $requestId,
        'svc'  => 'api',
        'op'   => 'order.pay'
    ]
);
```

- Primary keys can be scalars or composite arrays (`['order_id' => 1, 'item_id' => 2]`); the helper normalizes them into a JSON-safe string.
- Use `recordDiff()` when you only care about changed keys; it stores a `_diff` structure in both columns (`before_data`/`after_data`) for readability.
- Metadata is merged with `Observability::withDefaults()` so `corr`, `tx`, `svc`, `op`, `actor` and driver info reach logs/traces consistently.

## 3. Track transaction phases

```php
$audit->recordTx('begin', ['corr' => $requestId, 'tx' => $db->transactionId()]);
// ... work ...
$audit->recordTx('commit', ['corr' => $requestId, 'tx' => $db->transactionId(), 'ms' => 42]);
```

Phases are free-form strings (`begin`, `commit`, `rollback`, etc.). Store correlation/transaction IDs so you can tie the row-level changes back to the transaction log.

## 4. Prune historical data

```php
$deleted = $audit->purgeOlderThanDays(90);
```

`purgeOlderThanDays()` deletes old rows from the `changes` table. Run it in batches (nightly or via cron) because large deletions can lock the table for a while. For fine-grained control, wrap the call in retries or limit it per tenant/table.

## 5. Hardening tips

- Keep the audit tables in their own schema/database if you want stricter access controls; pass the fully qualified names to the constructor (`tblChanges: 'audit.changes'`).
- When you store personally identifiable information, consider encrypting fields before calling `record()` or redact them (`['email' => '***']`) to avoid leaking sensitive data downstream.
- Emit the same `meta` array you pass to repositories/services so tracing systems can stitch the events back to HTTP requests, queues, or CLI runs.
