# PHPUnit Test Notes (MySQL focus)

> Quick reference for what the “Run 1” unit suite exercises, how it is configured, and why it matters.

## Command
- `docker compose run --rm app-mysql vendor/bin/phpunit -c tests/phpunit.xml.dist tests/Unit`
- Environment comes from `tests/phpunit.bootstrap.php` (sets DSNs, replica shim, MySQL defaults).
  - MySQL DSN: `mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4`
  - User/pass: `root`/`root`
  - Replica: auto-shimmed to the same DSN (unless `BC_REPLICA_*` provided) so replica-sensitive tests run.
  - Timeouts: MySQL session tuned via bootstrap; max_execution_time set per test run.

## Scope of the Unit Suite
- **Support utilities:** OrderByTools/OrderCompiler/SqlIdentifier (dialect-aware quoting), Search (LIKE/ESCAPE), SqlSplitter (DELIMITER/dollar-quoting), SqlPreview (whitespace collapse), Telemetry (errorFields/sampling).
- **Services:** SeekAndBulkSupport (keyset pagination capability, bulk upsert fallback, row-lock fallback → returns `null` when lock unavailable).
- **Tenancy:** TenantScope + Criteria integration (single/multi-tenant filters, attach/guard semantics).
- **Orchestrator:** Locking and registry interaction without installing umbrella DDL.

### Unit suite inventory (unique tests)
- Core: `MemoryCacheTest`, `QueryCacheTest`, `QueryCacheMetricsTest` – cache hits/evictions, metric accounting.
- Events: `CrudEventTest` – event payload normalization and tenant scoping.
- Idempotency: `InMemoryIdempotencyStoreTest` – in-memory store semantics (seen tokens, TTL).
- Installer: `DdlGuardTest` – parses/validates CREATE VIEW heads, directive enforcement (MySQL vs PG).
- Outbox: `OutboxRecordTest` – DTO shape and JSON fields.
- Packages: `CriteriaTest`, `SupportCriteriaTest`, `PerRepoCriteriaFromDbTest`, `JoinsAliasValidationTest`, `MapperRoundTripDynamicTest` – filter/sort/search parsing, join alias validation, mapping round-trips.
- ReadReplica: `RouterTest` – routing decisions (stickiness, replica fallback).
- Services: `SeekAndBulkSupportTest`, `OrchestratorTest` – optional capabilities and lock/registry paths.
- Support:
  - `BinaryCodecTest`, `CastsTest` – binary/typed casting helpers.
  - `JsonFiltersTest` – JSON path filters.
  - `ObservabilityTest`, `TelemetryTest`, `OperationResultTest`, `OperationResultTraceTest` – logging/telemetry fields, op result envelopes.
  - `OrderByToolsTest`, `OrderCompilerTest`, `SqlIdentifierTest`, `SqlDialectTest`, `SqlExprTest` – dialect-aware ORDER BY/identifier quoting and expression helpers.
  - `SearchTest`, `SqlSplitterTest`, `SqlPreviewTest` – LIKE/ESCAPE, statement splitting (DELIMITER, dollar-quoted), preview formatting.
- Tenancy: `TenantScopeTest` – tenant filters, attach/guard, criteria integration.

### Notable assertions (what they guard)
- **Order/Identifier helpers:** Expect backticks on MySQL, double quotes on PG → catches accidental PG-only SQL in shared code.
- **Search/SqlSplitter:** Validates escaping `%`, `_`, `\`, custom delimiters, PG dollar-quoting → prevents broken migrations and unsafe LIKE clauses.
- **SqlPreview:** Ensures previews don’t leak multi-line SQL or collapse comments incorrectly.
- **Telemetry:** Checks that SQLSTATE/driver codes bubble up from nested PDOExceptions for observability.
- **SeekAndBulkSupport:** Enforces presence of `SeekPaginableRepository`/`BulkUpsertRepository` and graceful fallbacks when missing capabilities.
- **TenantScope:** Verifies tenant filters and attach/guard behavior for single vs multi-tenant scopes.
- **Orchestrator (unit posture):** Confirms lock acquisition and registry wiring; does not load umbrella schema here.

## OrchestratorTest specifics
- Uses deterministic advisory lock name `blackcat:orch:<dbid>[:<extra>]`; no random suffixes.
- Points `BC_SCHEMA_DIR` to an empty temp directory to avoid pulling umbrella schema in this unit layer.
- Explicitly releases the installer lock for the test tag before running.
- Verifies status/installer paths; full installer coverage (tables/views) belongs to integration runs.

## Why these checks matter
- **MySQL quoting vs Postgres:** Tests assert backtick vs double-quote behavior so helpers don’t assume PG-only syntax.
- **Safe SQL construction:** Search/Order/Identifier/Splitter/Preview guard against malformed SQL, unsafe escapes, and delimiter edge cases.
- **Lock visibility:** Deterministic lock names surface real contention instead of hiding it behind random tokens.
- **Optional capabilities:** SeekAndBulkSupport only activates when repos implement `SeekPaginableRepository` or `BulkUpsertRepository`; tests ensure graceful fallbacks.
- **Tenant safety:** TenantScope asserts that tenant filters are present and consistent before writes.
- **Observability:** Telemetry/Observability helpers must propagate SQLSTATE and codes to logs; tests catch silent drops.

## When to use integration tests
- If you need to validate DdlGuard/view directives, installer ordering, or feature views, run the integration suites (schema + views installed from umbrella). Unit suite intentionally avoids loading real DDL to stay fast and focused.
- Integration command examples:
  - `docker compose run --rm app-mysql vendor/bin/phpunit -c tests/phpunit.xml.dist tests/Integration`
  - `docker compose run --rm app-mysql vendor/bin/phpunit -c tests/phpunit.xml.dist tests/Integration/Installer/DdlGuardViewDirectivesTest.php`
- Integration runs should start from a clean DB (`DROP/CREATE test`) and set `BC_INCLUDE_FEATURE_VIEWS=1` when feature views are expected.

### Integration suites (what to expect once green)
- **Installer/DdlGuard**: full umbrella schema install (tables + contract/feature views), validates MySQL view directives, fence checks, and dependency ordering across modules. Current blocker: `InstallAndStatusTest` fails because `vw_rbac_user_access_summary` is created before `rbac_user_roles` exists.
- **Repository CRUD / dynamic tests**: exercise repositories against real tables (upsert/lock/unique constraints) to catch missing columns/PKs/FKs in maps.
- **Outbox/Inbox/Events**: real JSON payload validation, scheduling, and dead-letter/retry paths.
- **Computed columns / feature views**: ensure views with derived columns match expected behavior after full install (sessions `is_active`, coupons `is_current`, etc.).
- **Service helpers**: ServiceHelpers, AuditTrail, replication/lag metrics with real schema data.

Run integration after schema/view changes to confirm installer + DdlGuard behaviors; keep unit fast for inner-loop edits.
