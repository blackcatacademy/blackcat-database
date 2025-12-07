# Schema Authoring Guidelines (MySQL/Postgres)

> Practical notes to keep installs/tests predictable and to avoid installer drift.

## Views (MySQL/MariaDB)
- Always declare `ALGORITHM=MERGE|TEMPTABLE` **and** `SQL SECURITY INVOKER`. `ALGORITHM=UNDEFINED` is rejected.
- Clause order matters on MySQL: `CREATE ALGORITHM=… SQL SECURITY … VIEW … AS …`.
- Use the umbrella maps (`schema-views-*.yaml`, `schema-views-feature-*.yaml`) for SQL; don’t hand-roll `CREATE VIEW … SELECT * …` in modules.
- Split tool guardrails: `scripts/schema-tools/Split-SchemaToPackages.ps1` emits warnings when a MySQL view lacks `ALGORITHM` or `SQL SECURITY` (regular + feature maps). Treat warnings as blockers.

## Install ordering
- **Tables before views.** Installer will fail fast if a view references a missing table; retries won’t mask missing DDL.
- Feature views belong in `schema-views-feature-*.yaml`; contract views in `schema-views-*.yaml`. Both sets must live in a package that matches the owner table.

## Locks & orchestration
- Orchestrator advisory lock: `blackcat:orch:<dbid>[:<extra>]` (deterministic). Avoid random suffixes; they hide contention.
- For MySQL lock debugging: check `performance_schema.metadata_locks` and `SHOW PROCESSLIST` to identify holders of user-level locks.

## Testing posture
- Unit tests can point `BC_SCHEMA_DIR` to an empty directory to avoid pulling umbrella DDL; they verify orchestration logic (locks, registry) without full schema.
- Integration suites should provision the real schema (tables + views) to exercise DdlGuard and installer ordering end-to-end.
