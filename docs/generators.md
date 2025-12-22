# Generators

The schema that powers every module lives under `./scripts/schema/`. We keep dialect-specific metadata files and then fan them out into package SQL, docs, and PHP classes. This page captures the intended pipeline so regenerations are deterministic.

## 1. Canonical inputs

| File | Purpose |
| --- | --- |
| `schema-map-postgres.yaml`, `schema-map-mysql.yaml` | Master table/view definitions per dialect. |
| `schema-defs-*.yaml`, `schema-seed-*.yaml`, `schema-views-*.yaml` | Column metadata, seed data and view directives consumed by the generators. |
| `templates/php/*.yaml` | PHP scaffolding templates for repositories, services, DTOs, installers, joins, etc. |

> Tip: keep both dialect maps in sync – most scripts accept `-MapPath` / `-DefsPath` so you can pass either Postgres or MySQL inputs explicitly.

## 2. Refresh schema & cleanup

```powershell
pwsh ./scripts/schema-tools/mk-schema.ps1 -SeedInTransaction -Force
pwsh ./scripts/schema-tools/Cleanup-SchemaFolders.ps1 -Force
```

`mk-schema.ps1` recalculates the monolithic schema maps (tables + seeds). `Cleanup-SchemaFolders.ps1` removes stale generated folders so subsequent steps start from a clean slate.

## 3. Split into packages & docs

Run the following for each dialect (replace the `-MapPath` / `-DefsPath` arguments accordingly):

```powershell
pwsh ./scripts/schema-tools/Split-SchemaToPackages.ps1 `
  -MapPath ./scripts/schema/schema-map-postgres.yaml `
  -PackagesDir ./packages

pwsh ./scripts/docs/New-PackageReadmes.ps1 `
  -MapPath ./scripts/schema/schema-map-postgres.yaml `
  -PackagesDir ./packages -Force

pwsh ./scripts/schema-tools/Build-Definitions.ps1 `
  -MapPath ./scripts/schema/schema-map-postgres.yaml `
  -DefsPath ./scripts/schema/schema-defs-postgres.yaml `
  -PackagesDir ./packages -Force

pwsh ./scripts/docs/New-PackageChangelogs.ps1 `
  -MapPath ./scripts/schema/schema-map-postgres.yaml `
  -PackagesDir ./packages -Force

pwsh ./scripts/docs/New-DocsIndex.ps1 `
  -MapPath ./scripts/schema/schema-map-postgres.yaml `
  -PackagesDir ./packages `
  -OutPath ./PACKAGES.md -Force
```

Repeat the same block with `schema-map-mysql.yaml` / `schema-defs-mysql.yaml` to refresh MySQL/MariaDB artifacts. When both vendors are up-to-date, rerun `PACKAGES.md` once more to include every module.

## 4. Generate PHP from schema

`Generate-PhpFromSchema.ps1` consumes the schema metadata and PowerShell templates under `scripts/templates/php`. Recommended invocation:

```powershell
pwsh -NoProfile -File ./scripts/schema-tools/Generate-PhpFromSchema.ps1 `
  -TemplatesRoot ./scripts/templates/php `
  -ModulesRoot   ./packages `
  -SchemaDir     ./scripts/schema `
  -EnginePreference auto `
  -FailOnViewDrift `
  -StrictSubmodules `
  -Verbose
```

Useful options:
- `-TreatWarningsAsErrors` – make template warnings fail the run.
- `-FailOnStale` – scans generated PHP for legacy patterns listed in the script.
- `-JoinPolicy left|all|any` – controls how FK-based joins are emitted.
- `-AllowUnresolved` – temporarily skip placeholder enforcement when iterating on templates.

Run with `-WhatIf` first if you want a dry-run diff preview.

## 5. Smoke tests & linting

After regeneration:

```bash
vendor/bin/phpunit
pwsh ./scripts/quality/Test-PackagesSchema.ps1
pwsh ./scripts/quality/Test-SchemaOutput.ps1
bash  ./scripts/quality/SqlLint-Diff.sh
```

CI runners mirror the same steps and provide Docker Compose helpers (`app-mysql`, `app-postgres`, `app-mariadb`) when you need isolated environments:

```bash
docker compose run --rm -e BC_DB=postgres app php ./tests/ci/run.php
docker compose run --rm app composer dump-autoload -o
```

Benchmarks (`pwsh ../blackcat-monitoring/bench/Run-Bench.ps1 ...`) and doc rebuilds (`/docs regenerate` slash-command) are also available once the schema/code generation succeeds.
