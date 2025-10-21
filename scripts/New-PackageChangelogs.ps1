<# New-PackageChangelogs.ps1 (clean & lint-friendly)
   Builds per-package CHANGELOG.md from git history (Conventional Commits).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $MapPath,
  [Parameter(Mandatory = $true)] [string] $PackagesDir,
  [string] $FromRef,                 # e.g. v1.0.0 (optional)
  [string] $ToRef = 'HEAD',
  [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path -LiteralPath $MapPath))     { throw "Map not found: $MapPath" }
if (!(Test-Path -LiteralPath $PackagesDir)) { throw "PackagesDir not found: $PackagesDir" }

$map    = Import-PowerShellDataFile -Path $MapPath
$tables = $map.Tables.Keys | Sort-Object

function Get-PackageSlug {
  param([string] $t)
  ($t -replace '_','-')
}

function Get-Range {
  param([string] $From, [string] $To)
  if ([string]::IsNullOrWhiteSpace($From)) { return $null }
  "$From..$To"
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
    if (!(Test-Path -LiteralPath $pkgPath)) {
      Write-Warning ("SKIP [{0}] – package not found: {1}" -f $t, $pkgPath)
      continue
    }

    # one record = one commit (incl. body), RS = 0x1E
    $prettyFormat = 'format:%H%x09%ad%x09%s%x09%b%x1E'
    $prettyArg    = "--pretty=$prettyFormat"
    $gitArgs = @('log', '--no-merges', '--date=short', $prettyArg)
    if ($range) { $gitArgs += $range }
    $gitArgs += @('--', $pkgPath)

    $stdout = & git @gitArgs 2>$null
    if ($null -eq $stdout) { $stdout = @() }

    $blob    = [string]::Join("`n", $stdout)
    $records = @($blob -split [char]0x1E | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

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
          # žádné backticky v PowerShell řetězci; formátujeme přes -f
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
      Set-Content -Path $path -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
      Write-Host ("WROTE [{0}] -> {1}" -f $t, $path)
    }
  }
  catch {
    Write-Warning ("FAILED [{0}]: {1}" -f $t, $_.Exception.Message)
  }
}