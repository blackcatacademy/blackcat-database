<#  
  New-DocsIndex.ps1
  Generates a root markdown index of all packages from schema/schema-map-postgres.yaml.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $MapPath,
  [Parameter(Mandatory = $true)] [string] $PackagesDir,
  [string] $OutPath = 'PACKAGES.md',
  [switch] $Force,
  [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $MapPath))     { throw "Map not found: $MapPath" }
if (!(Test-Path -LiteralPath $PackagesDir)) { throw "PackagesDir not found: $PackagesDir" }

$map    = Import-PowerShellDataFile -Path $MapPath
$tables = @($map.Tables.Keys | Sort-Object)

function Get-PackageSlug {
  param([string] $Table)
  $Table -replace '_','-'
}
function ConvertTo-TitleCase {
  param([string] $Name)
  $ti = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
  $ti.ToTitleCase(($Name -replace '[_-]+',' ').ToLowerInvariant())
}
function Get-Mark {
  param([string] $Path)
  if (Test-Path -LiteralPath $Path) { return '✅' } else { return '—' }
}
function Get-Rel {
  param([string] $Path)
  # Use a path relative to the repo root (the file is generated from the root).
  # If you do not need that precision, simply return the original $Path.
  return $Path -replace '\\','/'
}

# ---- build rows
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# BlackCat Database – Packages') | Out-Null
$lines.Add('') | Out-Null
function Get-StableMapStamp {
  param([Parameter(Mandatory=$true)][string]$MapPath)
  try {
    $sha = (& git log -1 --format=%h -- $MapPath 2>$null).Trim()
    if ($sha) { return "map@$sha" }
  } catch {}
  $mt = (Get-Item -LiteralPath $MapPath).LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') + 'Z'
  return "map@mtime:$mt"
}

$stamp = Get-StableMapStamp -MapPath $MapPath
$lines.Add(("> Generated from `{0}` ({1})." -f $MapPath, $stamp)) | Out-Null

$lines.Add('') | Out-Null

$lines.Add('| Table | Package | README | Definition | Changelog |') | Out-Null
$lines.Add('|-----:|:--------|:------:|:----------:|:---------:|') | Out-Null

foreach ($t in $tables) {
  $slug = Get-PackageSlug $t
  $pkg  = Join-Path $PackagesDir $slug

  $readmePath = Join-Path $pkg 'README.md'
  $defPath    = Join-Path $pkg 'docs\definition.md'
  $chgPath    = Join-Path $pkg 'CHANGELOG.md'

  $readmeLink = if (Test-Path -LiteralPath $readmePath) { "[README]({0})" -f (Get-Rel $readmePath) } else { '—' }
  $defLink    = if (Test-Path -LiteralPath $defPath)    { "[Definition]({0})" -f (Get-Rel $defPath) } else { '—' }
  $chgLink    = if (Test-Path -LiteralPath $chgPath)    { "[Changelog]({0})" -f (Get-Rel $chgPath) } else { '—' }

  $lines.Add(("| `{0}` | `{1}` | {2} | {3} | {4} |" -f $t, $slug, $readmeLink, $defLink, $chgLink)) | Out-Null
}

# ---- write
if ((Test-Path -LiteralPath $OutPath) -and -not $Force) {
  if (-not $Quiet) {
    Write-Host ("SKIP – {0} exists (use -Force)" -f $OutPath)
  }
} else {
  Set-Content -Path $OutPath -Value ($lines -join "`n") -Encoding UTF8 -NoNewline
  if (-not $Quiet) {
    Write-Host ("WROTE -> {0}" -f $OutPath)
  }
}
