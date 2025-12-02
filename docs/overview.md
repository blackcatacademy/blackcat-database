# Overview

BlackCat Database is a catalog of production-ready table modules that run on **PostgreSQL 13+**, **MySQL 8+** and **MariaDB 10.4+**. Each module ships with schema SQL, typed PHP repositories/services, and automation to ensure installs stay reproducible across environments.

## Layout & sources of truth
- `scripts/schema/schema-map-{dialect}.yaml` keep the canonical schema metadata (tables, views, seeds) for every supported database engine. The `scripts/schema/schema-*.yaml` files mirror dialect-specific definitions/seed/view metadata.
- `packages/<module>/` holds the generated PHP + SQL for a single logical table/view. Packages can be consumed individually or via the umbrella orchestrator.
- `docs/` (this folder) captures the operational knowledge: usage guide, CI cheatsheet, and task-focused how-to articles.
- `scripts/schema-tools/Generate-PhpFromSchema.ps1` plus the PowerShell templates under `scripts/templates/php/` turn the schema maps into repositories, DTOs, services, installers and tests. See `docs/generators.md` for the full pipeline.

## Runtime building blocks
- **Installer + DdlGuard** (`src/Installer.php`, `src/Support/DdlGuard.php`) manage module lifecycle with advisory locks, deterministic view creation, fence checks and view verification (`ViewVerificationException`) so drift is caught immediately.
- **Criteria, Search & OrderCompiler** (`src/Support/Criteria.php`, `Search.php`, `OrderCompiler.php`) provide safe WHERE/ORDER/LIMIT builders with tenant guards, JSON filters, keyset pagination and dialect-aware `NULLS FIRST/LAST` handling.
- **TenantScope** (`src/Tenancy/TenantScope.php`) enforces tenant filters for reads and writes, provides helper SQL fragments, and plugs directly into Criteria.
- **BulkUpsertTrait & UpsertBuilder** (`src/BulkUpsertRepository.php`, `src/Support/UpsertBuilder.php`) offer efficient single-row and bulk UPSERTs with automatic chunking, quoted identifiers, and optional `RETURNING` for vendors that support it.
- **AuditTrail** (`src/Audit/AuditTrail.php`) persists change events and transaction metadata with JSON payloads, observability tags, and installer helpers for both Postgres and MySQL/MariaDB backends.
- **IdempotentCrudService + Idempotency stores** (`src/Services/IdempotentCrudService.php`, `src/Idempotency`) wrap CRUD operations in idempotent guards backed by PDO/DB tables or in-memory stores, complete with retry-friendly statuses.
- **Installer helpers & templates** (see `scripts/templates/php/*.yaml`) keep generated repositories/services consistent, while `docs/howto/*.md` document advanced tasks such as SQL coverage, backoff, RBAC, feature flags and the new tenant/audit/idempotency helpers.

Use `docs/usage.md` for the day-to-day workflow and the `howto/` series for focused playbooks.
