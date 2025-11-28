## Schema view layers

We split SQL view definitions into clear layers so each change has a single owner and predictable blast radius:

- **Base** (`schema-views-<engine>.psd1`): one contract view per table, no joins. Canonical, shared by everyone.
- **Joins** (`schema-views-joins-<engine>.psd1`): multi-table analytics/metrics expected across services. Still first-party/standard.
- **Featured** (`schema-views-feature-<engine>.psd1`): shared extensions likely reused across multiple internal modules. Keep minimal.
- **Module featured** (`schema-views-feature-modules-<engine>.psd1`): per-module, domain-specific views (crypto, catalog, RBAC, replication, SLO). Owner is the module name (folder), not the underlying table.
- **External featured placeholders** (`schema-views-feature-<engine>-ext*.psd1`): reserved slots for external partners; start empty, reviewed before use.

File naming convention: `schema-views-<layer>-<engine>[suffix].psd1`, where `engine` is `mysql` or `postgres`. The generator loads all matching feature files (`schema-views-feature-<engine>*.psd1`) so module/external files are picked up automatically.

### Why centralize?
- **Security & reviewability:** one source of truth for view SQL; no hidden SQL in external repos. Easier static review and automated scanning.
- **Deterministic ownership:** base/joins are project-standard; module files belong to the owning team. External slots stay isolated and empty until vetted.
- **Compatibility:** engine-specific SQL lives here, not scattered. Adding another database later only requires adding its mapped files.

### Authoring rules
- Base: exactly one view per table, no joins, no business logic.
- Joins: only widely reusable multi-table views/metrics. Avoid tenant-specific hacks.
- Featured: only if genuinely shared across modules; otherwise use module featured.
- Module featured: Owner = module name (folder). If a view spans multiple modules, prefer joins/featured; avoid duplication.
- External featured (ext1/2/3): stay empty until an external module is reviewed; any addition must go through the same review/tests as internal code.

### Current module featured coverage (internal)
- Crypto: pq readiness, wrapper layers.
- Catalog: catalog health, coupon effectiveness.
- RBAC: access summary, sync cursors status, roles coverage, expiring assignments.
- Replication/monitoring: peer health, latest lag samples.
- SLO: last computed SLO status.

### Workflow hints
- When adding a view, choose the lowest layer that fits the reuse scope.
- Keep SQL in schemas; generators/templates should not invent SQL.
- Prefer MERGE vs TEMPTABLE in MySQL only when safe; set explicit `SQL SECURITY` as needed.
- Always run the schema generator after edits and review drift in generated PHP. Tests should validate new views where relevant.
