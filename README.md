# BlackCat Database (umbrella)

[![DB Docs](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-docs.yml/badge.svg?branch=main)](https://github.com/blackcatacademy/blackcat-database/actions/workflows/db-docs.yml)

![MySQL](https://img.shields.io/badge/SQL-MySQL%208.0%2B-4479A1?logo=mysql&logoColor=white)
![Status](https://img.shields.io/badge/status-stable-informational)
![License](https://img.shields.io/badge/license-BlackCat%20Proprietary-red)

A curated set of reusable MySQL 8.0 table packages. Each table lives in its own repository and is pulled here as a Git submodule. This umbrella repo provides a single place to browse, generate docs, and keep the packages in sync.

---

## What’s inside
- `scripts/` – generators (split schema, READMEs, column definitions, changelogs, index)
- `packages/` – table packages (each is a submodule with `schema/` + generated docs)
- `schema/` – monolithic CREATE statements (source of truth for generators)
- `PACKAGES.md` – index of all packages (generated)

> Browse all packages: **[PACKAGES.md](./PACKAGES.md)**

---

## Quick start
Clone with submodules and initialize:

```bash
git clone --recursive https://github.com/blackcatacademy/blackcat-database.git
cd blackcat-database
git submodule update --init --recursive
```

PowerShell 7+ is used for generators on any OS (`pwsh`).

---

## Generate & verify docs locally
These commands (run from repo root) regenerate package schemas and docs. They are the same steps CI uses to verify outputs are up‑to‑date.

```bash
pwsh ./scripts/Split-SchemaToPackages.ps1 `
  -MapPath ./scripts/schema-map.psd1 `
  -PackagesDir ./packages

pwsh ./scripts/New-PackageReadmes.ps1 `
  -MapPath ./scripts/schema-map.psd1 `
  -PackagesDir ./packages `
  -Force

pwsh ./scripts/Build-Definitions.ps1 `
  -MapPath ./scripts/schema-map.psd1 `
  -DefsPath ./scripts/schema-defs.psd1 `
  -PackagesDir ./packages `
  -Force

pwsh ./scripts/New-PackageChangelogs.ps1 `
  -MapPath ./scripts/schema-map.psd1 `
  -PackagesDir ./packages `
  -Force

pwsh ./scripts/New-DocsIndex.ps1 `
  -MapPath ./scripts/schema-map.psd1 `
  -PackagesDir ./packages `
  -OutPath ./PACKAGES.md `
  -Force
```

---

## Deterministic outputs
To keep CI noise‑free and cross‑OS consistent:
- Line endings are normalized to **LF** via `.gitattributes` / `.editorconfig` in both the umbrella and submodules.
- Generators use **stable header stamps** (schema map commit or file mtime), never the wall‑clock time.
- Scripts avoid trailing whitespace and ensure final newlines.

---

## Continuous Integration
The **DB Docs CI** workflow regenerates and verifies all artifacts on Linux & Windows, and fails the build if generated files differ from what’s committed.

- Workflow: [`.github/workflows/db-docs.yml`](./.github/workflows/db-docs.yml)
- Status badge is shown at the top of this README.

---

## Contributing
Please read **[CONTRIBUTING.md](./CONTRIBUTING.md)** and follow **Conventional Commits** for messages. If a generator reports that artifacts are out of date, run the steps in *Generate & verify docs locally* and commit both submodule updates and umbrella changes.

---

## Security
See **[SECURITY.md](./SECURITY.md)**. Do not open public issues for vulnerabilities.

---

## License
Distributed under **BlackCat Store Proprietary License v1.0**. See `LICENSE`.
