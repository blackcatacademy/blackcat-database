# View Library (joins & features)

Staging area for the future standalone repo `blackcat-view-library`. This is the single source of truth for join / feature views, separate from the core schema maps. Everything here is declarative and meant to be consumed by `blackcat-installer` (no module-level code execution).

## Layout
- Domain folders: `core/`, `auth-rbac/`, `commerce/`, `crypto/`, `monitoring/`, … (add more as needed).
- Each domain contains:
  - `joins-<dialect>.psd1` – join layer for a single dialect (`mysql` or `postgres`).
  - `feature-<dialect>.psd1` – feature/module views for that dialect.
  - `sample-*.psd1` – examples showing required metadata (`Owner`, `Tags`, `Requires`, `create`).
- `profiles.psd1` – profile/tag selector (placeholder; to be wired into installer filtering).

## Required metadata per view
- `Owner`    : module/folder name that owns the view.
- `Tags`     : e.g., `analytics`, `reporting`, `ops`, `security`, `poc`.
- `Requires` : tables/views that must exist before install.
- `create`   : SQL for the given dialect (include ALGORITHM / SQL SECURITY when applicable).

## Naming conventions
- Join maps: `joins-mysql.psd1`, `joins-postgres.psd1` (one dialect per file).
- Feature maps: `feature-mysql.psd1`, `feature-postgres.psd1`.
- Sample files must NOT start with `joins-` or `feature-` to avoid being auto-loaded.

## Current status
- `core/joins-*` and `core/feature-*` still hold the legacy maps; RBAC features live in `auth-rbac/feature-*.psd1`.
- Installer/generator are being shifted to read from this library; once stable, duplicate maps in `scripts/schema` will be removed.
- License/Contributing are local to this library (proprietary, tied to BlackCat Database/Installer).

## Roadmap
1) Split join/feature maps into domains and prune duplicates from `core/`.
2) Wire the installer to use profiles/tags from `profiles.psd1` (e.g., `full` for CI, subsets for runtime).
3) Extract this folder into the standalone repo `blackcat-view-library` (GitHub org `blackcatdatabase`) once stable; use as submodule/dependency in `blackcat-database`.
4) Add integrity/safety checks: hash/signature validation of map files before install, and stricter DDL guard rules for ALGORITHM/SECURITY/DEFINER.
5) Document contribution rules (lint/validation) and release process for the library.
