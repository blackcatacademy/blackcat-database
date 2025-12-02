# Contributing

## Workflow
- Make changes in the umbrella repo or in the relevant submodule.
- Run generators locally:
  - `pwsh ./scripts/docs/New-PackageReadmes.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -Force`
  - `pwsh ./scripts/schema-tools/Build-Definitions.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -DefsPath ./scripts/schema/schema-defs-postgres.yaml -PackagesDir ./packages -Force`
  - `pwsh ./scripts/docs/New-DocsIndex.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -Force`
  - Optionally `pwsh ./scripts/docs/New-PackageChangelogs.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -PackagesDir ./packages -Force`
- Ensure deterministic output (LF endings, no timestamps).
- Verify submodules are clean: `git submodule status` (no `-dirty`).

## Commit style
- Conventional Commits (e.g. `feat:`, `fix:`, `chore:`).
- For umbrella-only pointer bumps use: `chore(submodules): bump pointers after schema & README generation`.

## PR checklist
- CI green.
- No unintended schema changes.
