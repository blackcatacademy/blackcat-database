# View layering rules

- **Contract views**: `vw_<table>` without JOINs stay in the table's database package and are always generated/installed from `schema-views-*.yaml`.
- **Feature/aggregate views**: anything with JOINs lives in `schema-views-feature-*.yaml`; it is always generated into packages (when they exist). Installation is controlled by `BC_INCLUDE_FEATURE_VIEWS` (default `0`; set to `1` in tests). Missing package -> the view is skipped with a warning.
- **Naming**: feature views keep the feature prefix (`vw_rbac_user_access_summary`, `vw_catalog_health_summary` …); contract views are `vw_<table>`.
- **Dependencies**: feature views provide `dependencies()` derived from JOIN/FROM, so installation order is resolved correctly when `BC_INCLUDE_FEATURE_VIEWS=1`.
