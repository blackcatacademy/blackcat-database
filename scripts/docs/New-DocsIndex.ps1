<#  
  New-DocsIndex.ps1
  Generates a root markdown index of all packages from schema/schema-map-postgres.yaml.
#>
[CmdletBinding()]
param(
  [Parameter()] [string] $MapPath = 'scripts/schema/schema-map-postgres.yaml',
  [Parameter()] [string] $PackagesDir = 'packages',
  [string] $OutPath = 'PACKAGES.md',
  [string] $RepoUrl,
  [string] $MapRoot,
  [string] $PackagesRoot,
  [switch] $Force,
  [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-Map {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) { throw "Map not found: $Path" }
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -notin @('.yaml','.yml')) { throw "Unsupported map format: $ext (expected .yaml/.yml)" }

  if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    throw "ConvertFrom-Yaml is required to read '$Path' (install PowerShell 7+ or powershell-yaml)."
  }
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml)
}

if (!(Test-Path -LiteralPath $PackagesDir)) { throw "PackagesDir not found: $PackagesDir" }

$root = if ($MapRoot) { Resolve-Path -LiteralPath $MapRoot } else { Resolve-Path '.' }
# Packages root is either explicitly provided or defaults to PackagesDir relative to repo root.
$pkgRoot = if ($PackagesRoot) { Resolve-Path -LiteralPath $PackagesRoot } else { Resolve-Path -LiteralPath (Join-Path $root $PackagesDir) }
$mapPathResolved = Resolve-Path -LiteralPath (Join-Path $root $MapPath)
$packagesResolved = $pkgRoot

$map = Import-Map -Path $mapPathResolved
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
  $rel = [IO.Path]::GetRelativePath($root, (Resolve-Path -LiteralPath $Path))
  return $rel -replace '\\','/'
}

# ---- build rows
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# BlackCat Database – Packages') | Out-Null
$lines.Add('') | Out-Null
function Get-StableMapStamp {
  param([Parameter(Mandatory=$true)][string]$MapPath)
  try {
    # Prefer a content hash (stable even if commit history differs).
    $sha = (& git hash-object -t blob $MapPath 2>$null).Trim()
    if ($sha) { return "map@sha1:$sha" }
    # Fallback to last commit on the file (full SHA1 for clarity).
    $sha = (& git log -1 --format=%H -- $MapPath 2>$null).Trim()
    if ($sha) { return "map@sha1:$sha" }
  } catch {}
  $mt = (Get-Item -LiteralPath $MapPath).LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') + 'Z'
  return "map@mtime:$mt"
}

$stamp = Get-StableMapStamp -MapPath $MapPath
$lines.Add(("> Generated from `{0}` ({1})." -f $MapPath, $stamp)) | Out-Null

$lines.Add('') | Out-Null

$lines.Add('| Table | Package | README | Docs | Changelog |') | Out-Null
$lines.Add('|-----:|:--------|:------:|:----:|:---------:|') | Out-Null

$warns = New-Object System.Collections.Generic.List[string]
$counts = [PSCustomObject]@{ Tables = 0; WithReadme = 0; WithDocs = 0; WithChangelog = 0 }

foreach ($t in $tables) {
  $counts.Tables++
  $slug = Get-PackageSlug $t
  $pkg  = Join-Path $packagesResolved $slug

  $readmePath = Join-Path $pkg 'README.md'
  $defPath    = Join-Path $pkg 'docs\definitions.md'
  $chgPath    = Join-Path $pkg 'CHANGELOG.md'

  if (-not (Test-Path -LiteralPath $pkg)) {
    $warns.Add("WARN: package folder missing for table '$t' -> $pkg")
  }

  function Get-LinkForPath {
    param([string]$path)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $rel = Get-Rel $path
    if ($RepoUrl) { return ($RepoUrl.TrimEnd('/') + '/' + $rel) }
    return $rel
  }

  $readmeLink = $null
  $defLink    = $null
  $chgLink    = $null

  if ($rl = Get-LinkForPath $readmePath) { $readmeLink = "[README]($rl)"; $counts.WithReadme++ }
  if ($dl = Get-LinkForPath $defPath)    { $defLink    = "[Docs]($dl)";    $counts.WithDocs++ }
  if ($cl = Get-LinkForPath $chgPath)    { $chgLink    = "[Changelog]($cl)"; $counts.WithChangelog++ }

  if (-not $readmeLink) { $readmeLink = '—' }
  if (-not $defLink)    { $defLink    = '—' }
  if (-not $chgLink)    { $chgLink    = '—' }

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

if ($warns.Count -gt 0 -and -not $Quiet) {
  $warns | ForEach-Object { Write-Warning $_ }
}
if (-not $Quiet) {
  Write-Host ("Summary: tables={0}, readme={1}, docs={2}, changelog={3}" -f $counts.Tables, $counts.WithReadme, $counts.WithDocs, $counts.WithChangelog)
}
