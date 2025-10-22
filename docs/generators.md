
`docs/generators.md`
```md
# Generators

- Split-SchemaToPackages.ps1 → writes `schema/001/020/030` to each package
- New-PackageReadmes.ps1     → README per package
- Build-Definitions.ps1      → docs/definition.md (columns metadata)
- New-PackageChangelogs.ps1  → CHANGELOG.md per package
- New-DocsIndex.ps1          → root PACKAGES.md

Run order (umbrella root):
```bash
pwsh ./scripts/Split-SchemaToPackages.ps1 -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages
pwsh ./scripts/New-PackageReadmes.ps1      -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -Force
pwsh ./scripts/Build-Definitions.ps1       -MapPath ./scripts/schema-map.psd1 -DefsPath ./scripts/schema-defs.psd1 -PackagesDir ./packages -Force
pwsh ./scripts/New-PackageChangelogs.ps1   -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -Force
pwsh ./scripts/New-DocsIndex.ps1           -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -OutPath ./PACKAGES.md -Force

 pwsh ./scripts/mk-schema.ps1 -MapPath ./scripts/schema-map.psd1 -OutDir ./schema -Force