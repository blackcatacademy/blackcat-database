<# New-PackageChangelogs.ps1 (clean & lint-friendly)
   Builds per-package CHANGELOG.md from git history (Conventional Commits).
#>
[CmdletBinding()]
param(
  [string] $MapPath = 'scripts/schema/schema-map-postgres.yaml',
  [string] $PackagesDir = 'packages',
  [string] $ViewsLibraryRoot = 'views-library',
  [string] $FromRef,                 # e.g. v1.0.0 (optional)
  [string] $ToRef = 'HEAD',
  [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Support psd1 or yaml maps
function Import-Map {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Map not found: $Path" }
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  switch ($ext) {
    '.yaml' { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml) }
    '.yml'  { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml) }
    default { throw "Unsupported map format: $ext (expected .yaml/.yml)" }
  }
}

if (!(Test-Path -LiteralPath $MapPath))     { throw "Map not found: $MapPath" }
if (!(Test-Path -LiteralPath $PackagesDir)) { throw "PackagesDir not found: $PackagesDir" }

$map    = Import-Map -Path $MapPath
$tables = $map.Tables.Keys | Sort-Object
# repo root plus helpers for relative paths and detecting "pure submodule pointer" changes
$repoRoot = (Resolve-Path .).Path
function Get-RelativePath {
  param([Parameter(Mandatory=$true)][string]$Path)
  [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path $Path).Path)
}
function ConvertTo-GitPath {
  param([Parameter(Mandatory=$true)][string]$Path)
  # convert backslashes to forward slashes, strip the leading ./
  return (($Path -replace '\\','/') -replace '^\./','')
}

function Test-PureSubmodulePointer {
  param(
    [Parameter(Mandatory=$true)][string]$Sha,
    [Parameter(Mandatory=$true)][string[]]$RelPaths
  )
  $paths = @($RelPaths | Where-Object { $_ })
  if ($paths.Count -eq 0) { return $false }
  $raw = & git diff-tree --raw -r $Sha -- @($paths) 2>$null
  if ($null -eq $raw) { return $false }
  $pending = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $paths) { $null = $pending.Add($p) }
  foreach($line in $raw){
    if ($pending.Count -eq 0) { break }
    if ($line -match '^\:(?<m1>\d{6})\s+(?<m2>\d{6})\s+[0-9a-f]{40}\s+[0-9a-f]{40}\s+\w+\s+(?<p>.+)$') {
      $pGit = ($matches.p -replace '\\','/')
      if ($pending.Contains($pGit) -and $matches.m1 -eq '160000' -and $matches.m2 -eq '160000') {
        $null = $pending.Remove($pGit)
      } else {
        return $false
      }
    }
  }
  return ($pending.Count -eq 0)
}

function Get-PackageSlug {
  param([string] $t)
  ($t -replace '_','-')
}

function Get-Range {
  param([string] $From, [string] $To)
  if ([string]::IsNullOrWhiteSpace($From)) { return $null }
  "$From..$To"
}

function Get-LogRecords {
  param([string[]] $GitArgs)
  $stdout = & git @GitArgs 2>$null
  if ($null -eq $stdout) { $stdout = @() }
  $blob = [string]::Join("`n", $stdout)
  return @($blob -split [char]0x1E | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$range = Get-Range -From $FromRef -To $ToRef

# Conventional sections → commit types
$sections = [ordered]@{
  'Features' = @('feat')
  'Fixes'    = @('fix')
  'Perf'     = @('perf')
  'Docs'     = @('docs')
  'Refactor' = @('refactor')
  'Chore'    = @('chore','build','ci','style','test','revert','other')
}

foreach ($t in $tables) {
  try {
    $slug    = Get-PackageSlug $t
    $pkgPath = Join-Path $PackagesDir $slug
    $pathsRel = @()
    if (Test-Path -LiteralPath $pkgPath) {
      $pathsRel += ConvertTo-GitPath (Get-RelativePath $pkgPath)
    }
    if ($ViewsLibraryRoot) {
      $viewLibCand = Join-Path $ViewsLibraryRoot $slug
      if (Test-Path -LiteralPath $viewLibCand) {
        $pathsRel += ConvertTo-GitPath (Get-RelativePath $viewLibCand)
      }
    }
    if ($pathsRel.Count -eq 0) {
      Write-Warning ("SKIP [{0}] – no paths found (package missing?)" -f $t)
      continue
    }
    if (!(Test-Path -LiteralPath $pkgPath)) {
      Write-Warning ("WARN [{0}] – package folder missing: {1} (will still include other paths if present)" -f $t, $pkgPath)
    }

    # one record = one commit (incl. body), RS = 0x1E
    $tabChar      = [char]0x09
    $recordSep    = [char]0x1E
    $prettyFormat = ("format:%H{0}%ad{0}%s{0}%b{1}" -f $tabChar,$recordSep)
    $prettyArg    = "--pretty=$prettyFormat"
    $gitArgs = @('log', '--no-merges', '--date=short', $prettyArg)
    if ($range) { $gitArgs += $range }
    $gitArgs += @('--')
    $gitArgs += $pathsRel

    $records = Get-LogRecords -GitArgs $gitArgs
    # If the superproject has no history for the paths (pure submodule), fall back to submodule log.
    if (($records.Count -eq 0) -and (Test-Path -LiteralPath (Join-Path $pkgPath '.git'))) {
      $gitArgsSub = @('-C', $pkgPath, 'log', '--no-merges', '--date=short', $prettyArg)
      if ($range) { $gitArgsSub += $range }
      $gitArgsSub += @('--', '.')
      $records = Get-LogRecords -GitArgs $gitArgsSub
    }

    $items = @()
    foreach ($rec in $records) {
      # hash \t date \t subject \t body...
      $parts = $rec -split "`t", 4
      if ($parts.Count -lt 3) { continue }

      $hash    = $parts[0].Trim()
      $date    = $parts[1].Trim()
      $subject = $parts[2].Trim()
      $body    = if ($parts.Count -ge 4) { $parts[3] } else { '' }

      $type  = 'other'
      $scope = ''

      if ($subject -match '^(?<type>\w+)(\((?<scope>[^)]+)\))?(!)?:') {
        $type  = $matches['type']
        $scope = $matches['scope']
      }
      $breaking = ($subject -match '!') -or ($body -match '(?m)^BREAKING CHANGE:')

      $shaShort = if ($hash.Length -ge 7) { $hash.Substring(0,7) } else { $hash }

      $items += [pscustomobject]@{
        Hash     = $hash
        ShaShort = $shaShort
        Date     = $date
        Type     = $type
        Scope    = $scope
        Subject  = $subject
        Breaking = $breaking
      }
    }

    # ---------- render ----------
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("## Changelog – {0}" -f $t)) | Out-Null
    $lines.Add("") | Out-Null

    $header = if ($range) { ("### Unreleased ({0})" -f $range) } else { ("### Unreleased (up to {0})" -f $ToRef) }
    $lines.Add($header) | Out-Null
    $lines.Add("") | Out-Null

    $hasAny = $false
    foreach ($kv in $sections.GetEnumerator()) {
      $title = $kv.Key
      $kinds = $kv.Value
      $rows  = @($items | Where-Object { $kinds -contains $_.Type })

      if ($rows.Count -gt 0) {
        $hasAny = $true
        $lines.Add(("#### {0}" -f $title)) | Out-Null
        foreach ($r in $rows) {
          $bang  = if ($r.Breaking) { ' **(BREAKING)**' } else { '' }
          $scTxt = if ([string]::IsNullOrWhiteSpace($r.Scope)) { '' } else { ("({0}) " -f $r.Scope) }
          # avoid backticks in the PowerShell string; use -f formatting instead
          $lines.Add(("- {0}: {1}{2}{3} — @[{4}]" -f $r.Date, $scTxt, $r.Subject, $bang, $r.ShaShort)) | Out-Null
        }
        $lines.Add("") | Out-Null
      }
    }

    if (-not $hasAny) {
      $lines.Add("_No changes in range._") | Out-Null
    }

    $path = Join-Path $pkgPath 'CHANGELOG.md'
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
      Write-Host ("SKIP [{0}] – CHANGELOG exists (use -Force)" -f $t)
    } else {
      Set-Content -Path $path -Value ($lines -join "`n") -Encoding UTF8 -NoNewline
      Write-Host ("WROTE [{0}] -> {1}" -f $t, $path)
    }
  }
  catch {
    Write-Warning ("FAILED [{0}]: {1}" -f $t, $_.Exception.Message)
  }
}
