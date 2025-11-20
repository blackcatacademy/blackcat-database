# Contributing

## Workflow
- Make changes in the umbrella repo or in the relevant submodule.
- Run generators locally:
  - `pwsh ./scripts/docs/New-PackageReadmes.ps1 -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -Force`
  - `pwsh ./scripts/schema-tools/Build-Definitions.ps1 -MapPath ./scripts/schema-map.psd1 -DefsPath ./scripts/schema-defs.psd1 -PackagesDir ./packages -Force`
  - `pwsh ./scripts/docs/New-DocsIndex.ps1 -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -Force`
  - Optionally `pwsh ./scripts/docs/New-PackageChangelogs.ps1 -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -Force`
- Ensure deterministic output (LF endings, no timestamps).
- Verify submodules are clean: `git submodule status` (no `-dirty`).

## Commit style
- Conventional Commits (e.g. `feat:`, `fix:`, `chore:`).
- For umbrella-only pointer bumps use: `chore(submodules): bump pointers after schema & README generation`.

## PR checklist
- CI green.
- No unintended schema changes.
