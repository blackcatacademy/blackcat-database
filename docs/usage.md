# Usage Guide

This guide is the single source of truth for developing, testing and operating the database modules across **PostgreSQL**, **MySQL 8+** and **MariaDB 10.4**.

> Tip: CI provides slash-commands for convenience (`/bench`, `/docs regenerate`, `/override`). See README for badges and links.

---

## 1. Setup

- Provide DSN via environment (or pass to scripts):  
  - Postgres: `pgsql:host=...;port=5432;dbname=...`  
  - MySQL/MariaDB: `mysql:host=...;port=3306;dbname=...`
- Set `DB_USER`, `DB_PASS` in CI secrets (and `DB_DSN_PG`/`DB_DSN_MY` if you keep them separate).

---

## 2. Running the test-suite

```bash
# Standard PHPUnit
vendor/bin/phpunit
```

- The matrix (PG/MySQL/MariaDB) runs in CI. Local runs target your default DSN.
- Useful helpers: `DbHarness`, `RowFactory`, `AssertSql`, `ConnFactory`.

---

## 3. Scaffolding new module (recommended shape)

> If you use templates/scripts, follow this layout:
```
packages/
  <Module>/
    src/ (repositories, services, DTOs, exceptions)
    schema/
      mysql/   (defs/ views/ seed/ map/)
      postgres/(defs/ views/ seed/ map/)
    tests/
    README.md
```
- Generate boilerplate from templates (`*.yaml` + `Generate-PhpFromSchema.ps1`), then implement repositories/services.
- Each package should expose a `ModuleInterface` and provide its `Installer` class.

---

## 4. Generic CRUD & Query Cache

- `GenericCrudService` provides typed CRUD and bulk operations; tune cache behavior via `QueryCache` (per DB vendor).  
- For deterministic ordering rely on **OrderCompiler** and `(created_at, id)` composite key where applicable.

---

## 5. Concurrency: Locks, NOWAIT, SKIP LOCKED

### Worker queue pattern (recommended)
**PostgreSQL / MySQL 8+**
```sql
SELECT id, payload
FROM jobs
WHERE status = 'queued'
FOR UPDATE SKIP LOCKED
LIMIT 50;
-- mark as processing and commit
```
- Avoid long transactions; idempotent updates with a worker token and `updated_at` watchdog.
- Fallback to `NOWAIT` when you need immediate failure instead of queueing.

### Deadlock-aware retry
- Use limited retries with exponential/backoff jitter; classify SQLSTATE (PG: `40P01`) and InnoDB deadlock errors to retry only where safe.

---

## 6. Pagination: Keyset vs OFFSET

**Keyset (stable, fast)**
```sql
-- DESC keyset on (created_at, id)
WHERE (created_at < :ts) OR (created_at = :ts AND id < :id)
ORDER BY created_at DESC, id DESC
LIMIT :page
```

**OFFSET (simple, but degrades)**
```sql
ORDER BY created_at DESC, id DESC
LIMIT :page OFFSET :off
```

Use keyset for feeds; keep composite index to match ordering.

---

## 7. Soft-delete-safe unique

**PostgreSQL**
```sql
CREATE UNIQUE INDEX ux_email_live ON users(email) WHERE deleted_at IS NULL;
```
**MySQL/MariaDB**
```sql
ALTER TABLE users ADD UNIQUE KEY ux_email_live (email, deleted_at);
-- ensure deleted_at is NULL for live rows (trigger or application rule)
```

---

## 8. Idempotent Retry (DDL/DML)

- Wrap transient operations with a retry helper; use SQLSTATE codes to decide:
  - PG: `40001` (serialization), `40P01` (deadlock) → safe to retry.
  - MySQL/MariaDB: `1213` (deadlock), `1205` (lock wait timeout) → retry with backoff.
- For DDL, apply `DdlGuard` with bounded attempts and audit logs.

---

## 9. Feature Flags in Views

- Create `flags` table and use CASE branches inside views to toggle behavior without code deploys.
- PHP helper: `scripts/support/FeatureFlags.php` (TTL cache).

---

## 10. TLS & DSN Hardening

- Prefer `sslmode=verify-full` (PG) or equivalent MySQL SSL settings.
- CI includes **TLS Matrix** workflow that verifies secure modes. Fix certificates/CA if secure modes fail.

---

## 11. Backups: Smoke Test

- PG: `pg_dump -Fc` + `pg_restore` into scratch DB, then row/table count checks.  
- MySQL/MariaDB: `mysqldump` + restore into `restore_smoke` DB and verify.

---

## 12. SQL Lint

- Uses **sqlfluff** on changed `.sql` files only.  
- Update `scripts/quality/sqlfluff-baseline.txt` if you need to suppress legacy violations; new ones still fail CI.

```bash
bash scripts/quality/SqlLint-Diff.sh
```

---

## 13. Benchmarks

### Local quick smoke
```bash
pwsh ./scripts/bench/Run-Bench.ps1 `
  -Dsn "$env:DB_DSN" -User "$env:DB_USER" -Pass "$env:DB_PASS" `
  -Mode seek -Concurrency 2 -Duration 10 -OutDir ./bench/results

python3 scripts/bench/Bench-Plot.py --glob "bench/results/*.csv" --outdir bench/plots
```

### PR commands
- `/bench quick` (2× threads, 10s), `/bench heavy` (16×, 120s)  
- Verdict based on **p95** vs repo SLO thresholds (`BENCH_P95_WARN`, `BENCH_P95_FAIL`).  
- On **FAIL**: label `bench:regression` (merge-blocking).

---

## 14. Perf Digest (PostgreSQL)

- Requires `pg_stat_statements` enabled. CI generates nightly digest with charts and (optional) Slack notification.

---

## 15. Slash Commands

- `/override` / `/unoverride` – maintainers can bypass merge gate for exceptional cases.  
- `/docs regenerate` – rebuild docs from templates and commit to PR.  
- `/bench ...` – run benchmarks and post artifacts.

---

## 16. Pitfalls (Quick Reference)

- Use **keyset** for pagination.  
- Prefer **SKIP LOCKED** workers; use **NOWAIT** for immediate-fail sections.  
- Collations: keep deterministic and consistent across joins; use functional indexes for case-insensitive search.  
- JSON: avoid unindexed path filters; use GIN (PG) or generated columns (MySQL).  
- Soft-delete + unique: partial unique (PG) or composite unique (MySQL).

---

## 17. DDL Guard & View Verification

- `DdlGuard` (`src/Support/DdlGuard.php`) wraps every `CREATE VIEW` issued by installers: it takes an advisory lock, retries with decorrelated backoff, fences until the view is queryable, and on MySQL/MariaDB it compares `ALGORITHM`, `SQL SECURITY`, and `DEFINER` directives. Drift triggers `ViewVerificationException` so CI fails instead of silently accepting mismatched views.
- Environment knobs: `BC_INSTALLER_LOCK_SEC`, `BC_INSTALLER_VIEW_RETRIES`, `BC_VIEW_FENCE_MS`, `BC_VIEW_IGNORE_DEFINER`. Set `BC_STRIP_DEFINER=1` / `BC_STRIP_ALGORITHM=1` / `BC_STRIP_SQL_SECURITY=1` to normalize vendor-specific headers before comparison.
- Installers default to `dropFirst=true`, so even without `OR REPLACE` the contract views are recreated deterministically. See `docs/howto/14_rbac-audit.md` and `docs/howto/18_audit-trail.md` for practical guard usage.

## 18. Tenant Scope & Multi-tenancy

- Use `TenantScope` (`src/Tenancy/TenantScope.php`) to express one- or multi-tenant filters once and reuse them everywhere. The helper exposes `apply(Criteria $c)`, raw `sql()/sqlSafe()` fragments, and `appendToWhere()` to patch plain SQL strings without forgetting parameters.
- For writes call `attach()` / `attachMany()` to enforce the tenant column and `guardRow()` / `guardIds()` for custom validation. Single-tenant scopes auto-fill the column; multi-tenant scopes require explicit values so accidental cross-tenant writes fail early.
- Pair it with generated repositories that expose `tenant_id` filters or call `$criteria->tenant($value)` so soft-deletes, joins and pagination continue to work. The new `docs/howto/17_tenant-scope.md` dives deeper into the patterns.

## 19. Idempotent CRUD & Stores

- `IdempotentCrudService` extends the generated CRUD services with `withIdempotency()` plus convenience wrappers (`createIdempotent`, `updateIdempotent`, `deleteIdempotent`, ...). Supply a stable key (e.g. request UUID) and it guarantees the wrapped operation runs exactly once across callers.
- Plug any `IdempotencyStore` implementation. `PdoIdempotencyStore` ships with the repo and persists keys in the `bc_idempotency` table using dialect-safe SQL (`ON CONFLICT DO NOTHING` / `ON DUPLICATE KEY UPDATE`). `InMemoryIdempotencyStore` is available for tests.
- Statuses follow `in_progress` → `success`/`failed` and errors from the store never block the main action (best effort). See `docs/howto/19_idempotent-crud.md` for schema snippets and orchestration tips.

## 20. Audit Trail & Observability

- `AuditTrail` centralizes change logging via two tables: `changes` (row-level before/after JSON) and `audit_tx` (transaction phases plus telemetry fields). Call `record()`, `recordDiff()` or `recordTx()` with observability metadata (`corr`, `svc`, `op`, `actor`, etc.) and the helper fills timestamps + JSON bindings safely across dialects.
- `installSchema()` sets up the audit tables (JSONB on PG, JSON/LONGTEXT on MySQL/MariaDB). Use `purgeOlderThanDays()` for retention and `recordDiff()` when only the delta matters.
- Combined with `Observability` helpers and `AuditTrail` metadata you can tie DB mutations back to HTTP requests, background jobs or CLI tools. Detailed instructions live in `docs/howto/18_audit-trail.md`.

## 21. Bulk UPSERT helpers

- Generated repositories can opt into `BulkUpsertTrait` (`src/BulkUpsertRepository.php`) which deduplicates columns across rows, respects definition whitelists, auto-detects conflict keys/`updated_at`, chunk-sizes updates (parameter-safe), and retries transient failures with exponential backoff.
- For single-row upserts use `UpsertBuilder::buildRow()` / `buildRowReturning()` + `UpsertBuilder::addReturning()` to append `RETURNING` when the server supports it (PG out of the box, MySQL ≥ 8.0.21, MariaDB ≥ 10.5).
- Traits/hooks such as `upsertUpdateColumns()`, `afterWrite()` and `invalidateSelfCache()` allow customization per repository. `docs/howto/20_bulk-upsert.md` contains full examples.
