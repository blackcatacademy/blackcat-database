# View layering rules

- **Contract views**: `vw_<table>` bez JOINů zůstávají v databázovém balíčku tabulky a jsou vždy generovány/instalovány z `schema-views-*.psd1`.
- **Feature/aggregate views**: cokoliv s JOINy je v `schema-views-feature-*.psd1`, vždy se generuje do balíčků (pokud existují); instalace je řízená env `BC_INCLUDE_FEATURE_VIEWS` (výchozí 0, v testech nastav na 1). Chybějící balíček -> view se přeskočí s warningem.
- **Naming**: feature views drž prefix feature (`vw_rbac_user_access_summary`, `vw_catalog_health_summary` …), kontraktní jsou `vw_<table>`.
- **Dependencies**: feature views mají `dependencies()` z JOIN/FROM, takže při instalaci s `BC_INCLUDE_FEATURE_VIEWS=1` se pořadí vyřeší správně.
