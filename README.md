![BlackCat Database](./.github/blackcat-database-banner.png)

# BlackCat Database · Release Channel

[![DB Docs](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-docs.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-docs.yml?query=branch%3Adev)
[![DB CI](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-ci.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-ci.yml?query=branch%3Adev)
[![Core CI](https://github.com/blackcatacademy/blackcat-database/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/ci.yml?query=branch%3Adev)
[![Lint PHP](https://github.com/blackcatacademy/blackcat-database/actions/workflows/lint.yml/badge.svg?branch=dev)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/lint.yml?query=branch%3Adev)

![MySQL](https://img.shields.io/badge/SQL-MySQL%208.0%2B-4479A1?logo=mysql&logoColor=white)
![MariaDB](https://img.shields.io/badge/SQL-MariaDB%2010.4.x-003545?logo=mariadb&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/SQL-PostgreSQL%2016-336791?logo=postgresql&logoColor=white)
![Status](https://img.shields.io/badge/status-stable-informational)
![License](https://img.shields.io/badge/license-BlackCat%20Proprietary-red)

Polished, ship-ready bundle of BlackCat table packages. Submodules are pinned to
their `main` branches, docs are pre-generated, and dev-only tooling is stripped
out. Need generators, infra, or CI harnesses? Jump to `dev`.

👉 See [SALES.md](./SALES.md) for a concise value deck and differentiators.

**Release highlights**
- Ready-to-run packages with generated docs (no local codegen required).
- Alignment across MySQL 8.0, MariaDB 10.4.x, PostgreSQL 16.
- Deterministic submodule SHAs; no CI workflows or infra clutter in this branch.
- Security, support, and licensing files stay first-class.

## Contents

- [What's inside](#whats-inside)
- [Repository map](#repository-map)
- [Quick start](#quick-start)
- [Working with packages](#working-with-packages)
- [Compatibility & runtime notes](#compatibility--runtime-notes)
- [Consumption patterns](#consumption-patterns)
- [Branch model](#branch-model)
- [Docs, support, license](#docs-support-license)

---

## What's inside

- Package submodules under `packages/`, pinned to their `main` branches.
- Generated docs (including `PACKAGES.md`) and runtime helpers in `src/`.
- Composer metadata for consumers; dev-only generators and infra stacks are not shipped here.
- Compliance files: LICENSE, NOTICE, SECURITY, SUPPORT, CODEOWNERS.
- Excluded: CI workflows, Terraform/K8s assets, scaffolding helpers, and PowerShell/PHP generators (all live in `dev`).

## Repository map

| Path | Description |
| --- | --- |
| `packages/` | Table packages (Git submodules), pinned for release. |
| `docs/` | Generated documentation and package catalog (`PACKAGES.md`). |
| `src/` | Runtime helpers and installers used by consumers. |
| `composer.json` | Runtime dependencies; no dev generators here. |
| `PACKAGES.md` | Catalog of modules included in this release. |

## Quick start

```bash
git clone --recursive https://github.com/blackcatacademy/blackcat-database.git -b release/main blackcat-database-release
cd blackcat-database-release
git submodule update --init --recursive
composer install --no-dev
```

- Package READMEs live in `packages/*/README.md`.
- Regeneration of docs/schemas is not available here; switch to `dev` for generators and CI workflows.

## Working with packages

- Start from [`PACKAGES.md`](./PACKAGES.md) to see the included modules and jump into `packages/<name>/README.md`.
- Runtime entry points are under `src/` (installers, helpers). Examples remain in `packages/*/docs`.
- To update a package pin: `git submodule update --remote packages/<name>` (ensure you’re on `release/main` and bump to the desired `main` SHA), then commit.
- Need schema changes or regenerated docs? Do the work on `dev`, run the generators there, and promote the result back into `release/main`.

## Compatibility & runtime notes

- Engines: MySQL 8.0+, MariaDB 10.4.x, PostgreSQL 16. See per-package READMEs for engine-specific notes.
- PHP: 8.3+ with PDO drivers for MySQL and PostgreSQL.
- Line endings and SQL formatting are already normalized (LF); no additional lint steps needed in this branch.
- Upgrade path: pull latest `release/main`, update submodules, and run your service migrations using the package scripts in `packages/*/schema`.

### Support matrix

| Area | Supported | Notes |
| --- | --- | --- |
| SQL engines | MySQL 8.0+, MariaDB 10.4.x, PostgreSQL 16 | Keep engine order in DDLs from package READMEs. |
| PHP runtime | 8.3+ | Composer install uses `--no-dev`; PDO MySQL/Postgres required. |
| Docs | Prebuilt in `docs/` + `PACKAGES.md` | Regenerate only on `dev`. |
| Line endings | LF | Already normalized across repo. |

## Consumption patterns

- **App integration:** require this umbrella (or individual packages) in your composer project, run `composer install --no-dev`, and wire the repositories/services from `src/`.
- **Migrations:** apply the DDL from `packages/<name>/schema/*.sql` in engine order; per-package README tables show the right files.
- **Docs & definitions:** `docs/` and `PACKAGES.md` are already built; treat them as the reference. If you need refreshed docs, switch to `dev`, regenerate, and cherry-pick into `release/main`.
- **Hotfix flow:** patch on `dev`, backport the minimal change set to `release/main`, and bump the affected submodule pins. Avoid committing regenerated assets in `release/main` unless they belong to the hotfix.

## Branch model

- `release/main`: production bundle with dev tooling removed; submodules pinned to their `main`.
- `dev`: full development branch with generators, CI workflows, and infrastructure assets. Make changes there and promote into `release/main`.

## Release operations (maintainers)

1) Work on `dev`: run generators, refresh docs, and bump package SHAs.  
2) Fast-forward `release/main` to the desired SHAs (submodules + root), commit pins.  
3) Smoke-test: install with `--no-dev`, run minimal schema apply against MySQL/Postgres.  
4) Push `release/main` and open a PR into `main` if your workflow requires review gates.  
5) Tag releases from `release/main` only after submodule pins and docs are stable.

## Docs, support, license

- Core docs remain available in `docs/` (overview, usage, package catalog). CI command references and generator guides live in `dev`.
- Issues and PRs should target `dev`; release updates are generated from there.
- Security: see [SECURITY.md](./SECURITY.md). License: [LICENSE](./LICENSE).
  For help, check [SUPPORT.md](./SUPPORT.md).
