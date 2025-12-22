![BlackCat Database](./.github/blackcat-database-banner.png)

# BlackCat Database (Umbrella)

[![DB Docs](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-docs.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-docs.yml?query=branch%3Adev)
[![DB CI](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-ci.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-ci.yml?query=branch%3Adev)
[![Core CI](https://github.com/blackcatacademy/blackcat-database/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/ci.yml?query=branch%3Adev)
[![Lint PHP](https://github.com/blackcatacademy/blackcat-database/actions/workflows/lint.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/lint.yml?query=branch%3Adev)

![MySQL](https://img.shields.io/badge/SQL-MySQL%208.0%2B-4479A1?logo=mysql&logoColor=white)
![MariaDB](https://img.shields.io/badge/SQL-MariaDB%2010.4.x-003545?logo=mariadb&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/SQL-PostgreSQL%2016-336791?logo=postgresql&logoColor=white)
![Status](https://img.shields.io/badge/status-stable-informational)
![License](https://img.shields.io/badge/license-BlackCat%20Proprietary-red)

Curated, reusable table packages with batteries included: schema definitions,
docs, changelogs, generators, and automation. Individual modules live in
`packages/` as Git submodules; this umbrella is the command center to author
schemas, regenerate documentation, run CI, and ship operational tooling across
MySQL 8.0, MariaDB 10.4, and PostgreSQL 16. Designed to be repeatable, observable,
and “push-to-green” for every database we support.

**Why this repo**
- Single source of truth for three engines (MySQL/MariaDB/PostgreSQL) with
  synchronized maps and views.
- Deterministic generators (PowerShell + PHP) that mirror what CI runs.
- Submodules kept lean: each package carries only its DDL/DTOs; this umbrella
  coordinates codegen, docs, and release hygiene.
- Built-in dev cockpit: [`scripts/dev/Dev-Workflow.ps1`](./scripts/dev/Dev-Workflow.ps1)
  provides a guided UI to split schemas, regenerate PHP/README/CHANGELOGs,
  run PHPUnit/DB suites, and launch services locally without memorizing the
  command matrix.
- Observability/ops assets live in
  [`blackcat-monitoring`](https://github.com/blackcatacademy/blackcat-monitoring)
  (Terraform/Kubernetes manifests, Prometheus rules, dashboards, dev stack).

---

## Contents

1. [Repository map](#repository-map)
2. [Getting started](#getting-started)
3. [Working with packages](#working-with-packages)
4. [Generators & automation scripts](#generators--automation-scripts)
5. [CLI utilities & scaffolding](#cli-utilities--scaffolding)
6. [Observability & infrastructure](#observability--infrastructure)
7. [Continuous integration](#continuous-integration)
8. [Contributing, security, license](#contributing)
9. [Doc snapshots](#doc-snapshots)

---

## Repository map

| Path | Description |
| --- | --- |
| [`packages/`](./PACKAGES.md) | All table packages (Git submodules). Browse the generated catalog in **[PACKAGES.md](./PACKAGES.md)**. |
| [`schema/`](./schema) | Monolithic CREATE statements that act as the source of truth for generators. |
| [`scripts/`](./scripts) | PowerShell / PHP helpers for splitting schemas, generating docs, linting SQL, etc. See [docs/generators.md](./docs/generators.md). |
| [`docs/`](./docs) | Human docs: [usage.md](./docs/usage.md), [overview.md](./docs/overview.md), [CI-COMMANDS.md](./docs/CI-COMMANDS.md), [generators.md](./docs/generators.md), bench dashboards, how-to guides, etc. |
| [`docs/ERD.md`](./docs/ERD.md) | Auto-rendered Mermaid ERD with FK lineage, hubs/linked/orphan styling, legend + stats. |
| [`docs/AUDIT.md`](./docs/AUDIT.md) | Package health snapshot (PK/IDX/FK coverage, views, scores) with links to each package. |
| [`blackcat-cli.json`](./blackcat-cli.json) | Component manifest consumed by `blackcat-cli` (exposes builtin `blackcat db ...`). |
| [`examples/`](./examples/README.md) | Service-level samples showing how to compose repositories (see [examples/README.md](./examples/README.md)). |
| [`tools/`](./tools/README.md) | Developer tooling such as the scaffold CLI. Details in [tools/README.md](./tools/README.md). |
| [`templates/`](./templates) | PHP scaffolding templates consumed by `tools/scaffold.php`. |
| [`tests/`](./tests) | Contract / integration suites for modules, installers, services, and orchestration helpers. |

---

## Getting started

```bash
git clone --recursive https://github.com/blackcatacademy/blackcat-database.git
cd blackcat-database
git submodule update --init --recursive
composer install
```

**Requirements**

- PHP 8.3+ with PDO MySQL/PostgreSQL extensions (dev + runtime)
- PowerShell 7 (`pwsh`) for cross-platform generators
- Databases:
  - MySQL 8.0+ (primary target)
  - MariaDB 10.4.x (explicitly pinned/covered in CI)
  - PostgreSQL 16 (full integration suite)
- Optional: Docker Compose for local matrix (`docker compose up app-mysql/app-postgres/app-mariadb`).

See [docs/usage.md](./docs/usage.md) for DB bootstrapping and runtime wiring.

**Quick CI parity (local)**

- Split schemas to packages and regenerate docs/definitions:
  ```bash
  pwsh ./scripts/schema-tools/Split-SchemaToPackages.ps1 -InDir ./scripts/schema -PackagesDir ./packages
  pwsh ./scripts/docs/New-PackageReadmes.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -Force
  pwsh ./scripts/docs/New-PackageChangelogs.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -Force
  ```
- PHPStan + PHPUnit DB suites (from containers):
  ```bash
  docker compose up -d mysql postgres mariadb
  docker compose run --rm app php vendor/bin/phpstan -c phpstan.neon
  docker compose run --rm app-mysql php vendor/bin/phpunit --configuration tests/phpunit.xml.dist --testsuite "DB Integration"
  docker compose run --rm app-postgres php vendor/bin/phpunit --configuration tests/phpunit.xml.dist --testsuite "DB Integration"
  docker compose run --rm app-mariadb php vendor/bin/phpunit --configuration tests/phpunit.xml.dist --testsuite "DB Integration"
  ```

---

## Working with packages

- **Browse modules** – start from [PACKAGES.md](./PACKAGES.md) or inspect
  individual package READMEs inside `packages/*/README.md`.
- **Outbox / audit / tenancy utilities** – see corresponding scaffolds generated
  via [`tools/scaffold.php`](./tools/scaffold.php) (documented
  [here](./tools/README.md)).
- **Runtime services** – helper traits, repositories, and installers live under
  `src/`. Important entry points:
  - [`src/Installer.php`](./src/Installer.php) for schema orchestration
  - [`src/Services/GenericCrudService.php`](./src/Services/GenericCrudService.php)
  - [`src/Support/Criteria.php`](./src/Support/Criteria.php)
  - Example: [`examples/UserRegisterService.php`](./examples/UserRegisterService.php)
- **Field-level encryption** – see [docs/CRYPTO-ADAPTER.md](./docs/CRYPTO-ADAPTER.md) for wiring into `blackcat-crypto` and automatic encrypt/HMAC on writes.

---

## Generators & automation scripts

The `scripts/` directory holds the same PowerShell modules used by CI:

| Script | Purpose |
| --- | --- |
| `schema-tools/Split-SchemaToPackages.ps1` | Decompose monolithic DDL from `schema/` into per-package migrations. |
| `schema-tools/Build-Definitions.ps1` | Produce column dictionaries + `definitions/` artifacts referenced by services. |
| `docs/New-PackageReadmes.ps1`, `New-PackageChangelogs.ps1`, `New-DocsIndex.ps1` | Generate documentation & aggregated changelogs, updating `PACKAGES.md`. |
| `schema-tools/Lint-Sql.ps1`, `Generate-MermaidERD.ps1`, `packages/Audit-Packages.ps1` | Misc tooling for linting, ERD diagrams, and package health. |

Usage examples and options live in [docs/generators.md](./docs/generators.md) and
[docs/usage.md](./docs/usage.md). To reproduce what CI does:

```bash
pwsh ./scripts/schema-tools/Split-SchemaToPackages.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages
pwsh ./scripts/docs/New-PackageReadmes.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -Force
pwsh ./scripts/schema-tools/Build-Definitions.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -DefsPath ./scripts/schema/schema-defs-postgres.yaml -PackagesDir ./packages -Force
pwsh ./scripts/docs/New-PackageChangelogs.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -Force
pwsh ./scripts/docs/New-DocsIndex.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -OutPath ./PACKAGES.md -Force
```

All scripts produce deterministic output (LF endings, stable headers, final
newline) to keep diffs clean across OSes.

---

## Doc snapshots

- **ERD** – see [`docs/ERD.md`](./docs/ERD.md) for the live Mermaid graph with FK lineage, hub/linked/orphan styling, legend, and stats (regenerated by `Generate-MermaidERD.ps1`).
- **Audit** – see [`docs/AUDIT.md`](./docs/AUDIT.md) for package health (PK/IDX/FK coverage, views, scores) with direct links to each package (regenerated by `Audit-Packages.ps1`).
- Both are rebuilt by the doc workflows alongside READMEs and changelogs; check `db-docs.yml` if you need to mirror CI locally.

---

## CLI utilities & scaffolding

- **Operational CLI**: centralized in `blackcat-cli` (optional).
  - `blackcat db ...` – ping/explain/route/wait/trace helpers for live databases.
  - `blackcat db doctor` – quick DB snapshot (driver, server, replica info).
  - `blackcat db outbox-worker` – long-running outbox dispatcher (stdout/webhook),
    PID/health files, and graceful signal handling.

- **Scaffolding** (`tools/scaffold.php`, documented in
  [tools/README.md](./tools/README.md)):
  - `make:module`, `make:service`, `make:repository`, `make:criteria`, etc.
  - `make:module-tests` for the full epic suite (upsert parity, keyset paging,
    DDL guard, observability…).
  - `make:audit-module`, `make:tenant-scope`, `make:replica-router` helpers.
  - `make:demo-data`, `make:howto`, and `make:all` convenience commands.

- **Examples** – [examples/UserRegisterService.php](./examples/UserRegisterService.php)
  demonstrates how to compose services with `ServiceHelpers`, transactional
  retries, and package repositories.

---

## Observability & infrastructure

Operational and observability assets (Terraform, Kubernetes manifests, Prometheus
rules, Grafana dashboards, dev stack) live in
[`blackcat-monitoring`](https://github.com/blackcatacademy/blackcat-monitoring).

Bench dashboards live under `docs/bench/` and can be regenerated via
`blackcat-monitoring/bench/**` helpers.

---

## Continuous integration

GitHub Actions drive reproducibility:

- **`db-docs.yml`** – regenerates schemas/docs and asserts cleanliness on Linux
  + Windows (tracking `dev`).
- **`db-ci.yml`** – full PHP + DB integration matrix across MySQL 8.0, MariaDB
  10.4.x, and PostgreSQL 16 (tracking `dev`), including codegen cleanliness.
- **`ci.yml` / `lint.yml` / `sql-lint.yml`** – static analysis, coding standards,
  and SQL lint checks to keep drift small before hitting DB CI.
- **`tls-matrix.yml`** – TLS compatibility matrix across drivers.
- **`bench-command.yml`, `pg-perf-digest.yml`** – optional perf/bench harnesses
  (enable as needed).
- Additional workflows (bench, chaos tests, TLS matrix, etc.) live under
  [`.github/workflows`](./.github/workflows).

For the commands executed by CI, consult [docs/CI-COMMANDS.md](./docs/CI-COMMANDS.md).

---

## Contributing

- Read [CONTRIBUTING.md](./CONTRIBUTING.md) and follow the coding standards +
  Conventional Commits.
- Keep submodules up to date; when generators say files changed, run the scripts
  listed above and commit both the umbrella and package diffs.
- Development helpers: see [tools/README.md](./tools/README.md) and
  [`blackcat-cli`](https://github.com/blackcatacademy/blackcat-cli).

## Security

Report vulnerabilities privately per [SECURITY.md](./SECURITY.md). Do not open
public issues for security-related topics.

## License

Distributed under **BlackCat Store Proprietary License v1.0**. See
[LICENSE](./LICENSE).
