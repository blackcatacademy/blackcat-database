param(
  [Parameter(Mandatory=$true)] [string] $ReadmePath,
  [Parameter(Mandatory=$true)] [string] $PackagesPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path $ReadmePath)) { throw "README not found: $ReadmePath" }
if (!(Test-Path $PackagesPath)) { throw "PACKAGES not found: $PackagesPath" }

$readme = Get-Content -Raw -Path $ReadmePath -Encoding UTF8
$pkgs = Get-Content -Raw -Path $PackagesPath -Encoding UTF8

# Parse table rows like:
# | [pkg](./packages/pkg) | `table` | 3 | 1 | 0 |
$pattern = '^\|\s*\[[^\]]+\]\([^)]+\)\s*\|\s*`[^`]+`\s*\|\s*(?<idx>\d+)\s*\|\s*(?<fk>\d+)\s*\|\s*(?<view>\d+)\s*\|$'
$pkgCount = 0
$idxTotal = 0
$fkTotal = 0
$viewTotal = 0

foreach ($line in ($pkgs -split "`r?`n")) {
  if ($line -match $pattern) {
    $pkgCount++
    $idxTotal  += [int]$matches['idx']
    $fkTotal   += [int]$matches['fk']
    $viewTotal += [int]$matches['view']
  }
}

$badgesStart = '<!-- AUTOBADGES:START -->'
$badgesEnd   = '<!-- AUTOBADGES:END -->'

if ($readme -notmatch [regex]::Escape($badgesStart) -or $readme -notmatch [regex]::Escape($badgesEnd)) {
  throw "Badge markers not found in README (<!-- AUTOBADGES:START --> ... <!-- AUTOBADGES:END -->)"
}

$newBadges = @"
$badgesStart
![Packages](https://img.shields.io/badge/packages-$pkgCount-blue)
![Indexes](https://img.shields.io/badge/indexes-$idxTotal-informational)
![FKs](https://img.shields.io/badge/FKs-$fkTotal-informational)
![Views](https://img.shields.io/badge/views-$viewTotal-informational)
$badgesEnd
"@.Trim()

# Replace the block between markers
$regex = [regex]"$([regex]::Escape($badgesStart)).*?$([regex]::Escape($badgesEnd))"
$updated = $regex.Replace($readme, $newBadges, 1)

$updated | Out-File -FilePath $ReadmePath -NoNewline -Encoding UTF8
Write-Host "Updated badges in $ReadmePath (packages=$pkgCount, indexes=$idxTotal, fks=$fkTotal, views=$viewTotal)"