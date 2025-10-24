# BlackCat Umbrella — Modular DB Guide

> **Audience:** engineers writing or integrating modules (packages/`table-*`) and higher‑level services.
>
> **Goal:** build plug‑and‑play tables with predictable generated code, while the umbrella layer gives you a safe, ergonomic runtime (transactions, locks, timeouts, retries, caching).

---

## 1) Big picture

```
+-----------------------------+       +-----------------------------+
|  Frontend / API handlers    |  -->  |  High-level Services        |
|  (Controllers, Jobs, CLI)   |       |  (or Actions)               |
+-----------------------------+       +-----------------------------+
                                             | use ServiceHelpers
                                             v
                                     +--------------------+
                                     | Generated Repos    |
                                     | + Criteria/Defs    |
                                     +--------------------+
                                             | uses
                                             v
                                     +--------------------+
                                     | Core Database      |
                                     | (safe PDO wrapper) |
                                     +--------------------+
                                              ^
                                              | optional
                                              v
                                     +--------------------+
                                     | QueryCache (PSR-16)|
                                     +--------------------+
```

- **Modules (packages/`table-*`)**: each package = one table + view + indexes/FKs, generated repository & helpers.
- **Umbrella layer** provides:
  - `Runtime` (DI bundle of Database, dialect, logger, cache)
  - `Orchestrator` (install/upgrade with locks & timeouts)
  - `ServiceHelpers` trait (txn/ro/lock/timeout/retry/explain/cache/keyset)
  - `GenericCrudService` (98% CRUD)
  - `ActionInterface` + `OperationResult` (uniform FE/BE contract)

---

## 2) Bootstrap

```php
use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Runtime;
use BlackCat\Core\Database\QueryCache; // wraps your PSR-16 cache

// 1) Initialize Database::init(...) in your app bootstrap (done elsewhere)
$db = Database::getInstance();
$dialect = $db->isPg() ? SqlDialect::postgres : SqlDialect::mysql;

// 2) Optional cache & logger
$psr16 = $yourFileCache;    // PSR-16 (FileCache)
$psr3  = $yourLogger;       // PSR-3
$qcache = new QueryCache($psr16, $psr16 /* LockingCacheInterface? */ , $psr3);

$rt = new Runtime($db, $dialect, $psr3, $qcache);
```

> **Tip:** Database already defaults to unbuffered MySQL queries and strict attributes to avoid RAM spikes.

---

## 3) Managing modules (migrations)

```php
use BlackCat\Database\Registry;
use BlackCat\Database\Orchestrator;

$registry = new Registry(
    new \BlackCat\Database\Packages\Users\UsersModule(),
    new \BlackCat\Database\Packages\UserProfiles\UserProfilesModule(),
    // ... add your module instances here
);

$orch = new Orchestrator($rt);

// 3.1 Install/upgrade ALL (with dependency order, advisory lock, timeout)
$orch->installOrUpgradeAll($registry);

// 3.2 Status overview
$st = $orch->status($registry); // ['modules'=>[], 'summary'=>['needsInstall'=>..,'needsUpgrade'=>..], ...]
```

**What Orchestrator adds:**
- Global advisory lock `schema:migrate` to avoid concurrent migration runs.
- Reasonable statement timeout around install/upgrade.
- Uses the same Installer you already have; safe defaults.

---

## 4) Generated code recap

Each package (e.g. `packages/users`) contains generated files:
- `src/UsersModule.php` — implements `ModuleInterface`; knows how to install/uninstall/status.
- `src/Repository.php` — safe CRUD (`insert`, `upsert`, `updateById`, `paginate`, ...).
- `src/Criteria.php` — whitelist filters/sort/search builder.
- `src/Definitions.php` — table/view names, columns, PK, unique keys, JSON cols, etc.
- `src/Dto/*.php` + Mapper — typed DTOs & mappers (optional in services if you prefer arrays).
- `src/Service/*` — **place for orchestration across multiple repos**. We’ll enhance these.

> Generátor se drží bezpečných defaultů (parametrizované SQL, sloupce přes whitelist, paging, optimistic locking když je version col, soft delete když existuje sloupec atd.).

---

## 5) Service layer (the ergonomic API)

### 5.1 ServiceHelpers trait

Add this to your service:

```php
use BlackCat\Database\Support\ServiceHelpers;

final class UsersAggregateService
{
    use ServiceHelpers; // expects private Database $db; optional private ?QueryCache $qcache

    public function __construct(
        private \BlackCat\Core\Database $db,
        private \BlackCat\Database\Packages\Users\Repository $users,
        private ?\BlackCat\Core\Database\QueryCache $qcache = null
    ) {}

    public function topUsers(): array {
        return $this->txnRO(function() {
            $sql = "SELECT id,email,score FROM users WHERE deleted_at IS NULL ORDER BY score DESC LIMIT 10";
            return $this->cacheRows($sql, [], 20); // uses QueryCache if present
        });
    }
}
```

**What you get for free:**
- `txn()` / `txnRO()` — transactions (RO on PG, safe fallback on MySQL)
- `withLock($name, $timeoutSec)` — advisory locks (MySQL `GET_LOCK`, PG advisory)
- `withTimeout($ms)` — per-scope statement timeout
- `retry($attempts)` — simple transient retry loop (deadlock/serialization)
- `keyset($sqlBase, $params, $pkCol, $after, $limit)` — keyset paging
- `explain($sql, $params, $analyze)` — `EXPLAIN`/`EXPLAIN ANALYZE` (PG JSON when available)
- `cacheRows($sql, $params, $ttl)` — via `QueryCache` (PSR‑16 under the hood)

### 5.2 GenericCrudService (98% cases)

```php
use BlackCat\Database\Services\GenericCrudService;

$usersCrud = new GenericCrudService(
    db: $db,
    repository: new \BlackCat\Database\Packages\Users\Repository($db),
    pkCol: 'id',
    qcache: $qcache,
    cacheNs: 'table-users'
);

$usersCrud->create(['email' => 'a@b.cz', 'password_hash' => '...']);
$usersCrud->getById(42, ttl: 15);
$usersCrud->updateById(42, ['display_name' => 'Neo']);
$usersCrud->deleteById(42);
```

This avoids repeating boilerplate; when you need custom workflows, write a specific service and still use `ServiceHelpers`.

### 5.3 Actions (one‑call from FE)

```php
use BlackCat\Database\Actions\OperationResult;

final class UserRegisterService
{
    use ServiceHelpers;
    public function __construct(
        private \BlackCat\Core\Database $db,
        private \BlackCat\Database\Packages\Users\Repository $users,
        private \BlackCat\Database\Packages\UserProfiles\Repository $profiles,
        private ?\BlackCat\Core\Database\QueryCache $qcache = null
    ) {}

    public function register(array $input): OperationResult
    {
        return $this->withLock('user:register:'.mb_strtolower($input['email'] ?? ''), 5, function() use ($input) {
            return $this->withTimeout(3000, function() use ($input) {
                return $this->retry(3, function() use ($input) {
                    return $this->txn(function() use ($input) {
                        $email = trim((string)($input['email'] ?? ''));
                        if ($email === '') return OperationResult::fail('Email required');

                        if ($this->db()->exists("SELECT 1 FROM users WHERE email = :e LIMIT 1", [':e'=>$email]))
                            return OperationResult::fail('Email already registered');

                        $now = (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s.u');
                        $this->users->insert([
                            'email' => $email,
                            'password_hash' => password_hash((string)($input['password'] ?? ''), PASSWORD_DEFAULT),
                            'created_at' => $now,
                            'updated_at' => $now,
                        ]);
                        $uid = $this->db()->lastInsertId();

                        $this->profiles->insert([
                            'user_id' => (int)$uid,
                            'display_name' => (string)($input['name'] ?? ''),
                            'created_at' => $now,
                            'updated_at' => $now,
                        ]);

                        return OperationResult::ok(['user_id'=>$uid], 'registered');
                    });
                });
            });
        });
    }
}
```

`OperationResult` is a small DTO: `{ ok: bool, message?: string, data: array }` — great for consistent API responses.

---

## 6) Caching strategy

- **PSR‑16 FileCache**: production‑ready, with file locks; inject into `QueryCache`.
- **QueryCache** provides:
  - `remember($key, $ttl, callable)` – generic value cache
  - `rememberRows($db, $sql, $params, $ttl)` – results of SELECT
  - Per‑DB key scoping (optional): build keys like `prefix:{$db->id()}:...` so multi‑DB apps don’t collide
- **Invalidation**: on writes use targeted invalidation (e.g. `delete(idKey)`), avoid global flush.

> TIP: Use `cacheNs` per table; compose keys as `ns:dbId:primaryKey` or from search params.

---

## 7) Transactions, locks, timeouts, retries

- Wrap multi‑repo workflows in `txn()`.
- Long reads → `txnRO()` + `withTimeout()`.
- Cross‑process critical sections → `withLock()`.
- Flaky conflicts (deadlocks/serialization) → `retry(3)` around the transactional lambda.
- Avoid unbounded `OFFSET` for deep pages → use `keyset()`.

---

## 8) Dialect notes (MySQL vs Postgres)

- **UPSERT**: Repos already generate the correct dialect: MySQL `ON DUPLICATE KEY`, PG `ON CONFLICT`.
- **Booleans**: DB layer binds types safely; mappers cast consistently.
- **Timestamps**: format `Y-m-d H:i:s.u` (works with `DATETIME(6)` / `timestamptz`).
- **Advisory locks**: `GET_LOCK` vs `pg_try_advisory_lock(hashtextextended(...))`.
- **Statement timeouts**: `SET LOCAL statement_timeout` (PG) vs `max_execution_time` (MySQL session).

---

## 9) Security & robustness

- Always pass params (no string concatenation of user data).
- Repos whitelist columns; mappers strictly cast types.
- Database wrapper disables emulated prepares by default.
- Unbuffered queries on MySQL to cap memory usage.
- Use `withStatementTimeout` for untrusted/complex filters.
- Consider `withAdvisoryLock` for idempotent workflows (e.g. payment webhooks).

---

## 10) Performance tips

- Create indexes for common `Criteria` filters; verify via `status()['missing_idx']` from modules.
- Prefer **keyset paging** for infinite feeds.
- Batch writes with `insertMany()` where possible.
- Keep rows slim in views used for listing.
- Use `QueryCache` for hot reads with conservative TTLs (5–30s) and targeted invalidation.

---

## 11) Writing a new module (package)

1. Create `packages/your_table/` and author your SQL schema files (`001_table.*.sql`, indexes, FKs, view).
2. Run the generator (your existing script) to create `Module`, `Repository`, `Criteria`, `Definitions`, etc.
3. Register the module in your bootstrap registry.
4. Install/upgrade with `Orchestrator`.
5. Write an aggregate `Service/*` that composes repositories for business workflows.

**Naming & versioning**
- Module `name()` should be `table-<snake>`; table is `<snake>`.
- Bump `version()` on schema changes; `Installer` records checksum in `_schema_registry`.
- Declare `dependencies()` for FK sources (e.g. `['table-users']`).

---

## 12) Testing & CI

- Use the provided `tests/ci/run.php` to install/upgrade/status across modules.
- In CI run 3 phases per dialect: install, idempotence pass, uninstall‑view smoke test.
- For services, unit‑test business flows by mocking `QueryCache` and using a temporary DB.

Minimal example:

```php
public function test_register_happy_path(): void {
    $db = Database::getInstance();
    $svc = new UserRegisterService($db, new UsersRepo($db), new ProfilesRepo($db));
    $res = $svc->register(['email'=>'x@y.z','password'=>'secret','name'=>'X']);
    $this->assertTrue($res->ok);
}
```

---

## 13) Troubleshooting

- **Migration race**: ensure you call `Orchestrator->installOrUpgradeAll()` once per deploy; advisory lock prevents parallel runs.
- **Slow queries**: enable DB debug logging, run `explain()`; add/adjust indexes.
- **Cache misses after writes**: make sure to invalidate per‑id keys in your service; `GenericCrudService` does it for you.
- **PG serialization failures**: wrap critical writes in `retry(3)`.

---

## 14) API reference (helpers)

From `ServiceHelpers`:
- `txn(callable): mixed` — RW transaction
- `txnRO(callable): mixed` — read‑only transaction (PG), safe fallback for MySQL
- `withLock(string $name, int $timeout, callable): mixed` — advisory lock
- `withTimeout(int $ms, callable): mixed` — statement timeout scope
- `retry(int $attempts, callable): mixed` — transient retry loop
- `keyset(string $sqlBase, array $params, string $pkCol, ?string $after, int $limit): array`
- `explain(string $sql, array $params=[], bool $analyze=false): array`
- `cacheRows(string $sql, array $params, int $ttl): array`

From `GenericCrudService`:
- `create(array $row): array {id: mixed}`
- `upsert(array $row): void`
- `updateById(int|string $id, array $row): int`
- `deleteById(int|string $id): int`
- `restoreById(int|string $id): int`
- `getById(int|string $id, int $ttl=15): ?array`
- `paginate(Criteria $c): array`

---

## 15) Conventions checklist

- [ ] Always use generated `Repository` for raw table ops.
- [ ] Write business workflows in `Service/*` using `ServiceHelpers`.
- [ ] Gate critical flows with `withLock()`.
- [ ] Add `retry()` around conflict‑prone sections.
- [ ] Prefer `txnRO()` for long reads.
- [ ] Use `QueryCache` for hot lists / lookups with short TTLs.
- [ ] Use `Orchestrator` for schema lifecycle.

---

**That’s it.** With these pieces you can expose very small, easy‑to‑use service APIs to frontend while retaining safety, performance and observability in the umbrella layer.

