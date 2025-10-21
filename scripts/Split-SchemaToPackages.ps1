param(
  [Parameter(Mandatory=$true)]
  [string]$MapPath,                                  # např. ./scripts/schema-map.psd1

  [string]$PackagesDir = (Join-Path $PSScriptRoot '..\packages'),
  [ValidateSet('detect','snake','kebab')]
  [string]$NameResolution = 'detect',                 # jak hledat složky: snake | kebab | detect (oboje)
  [switch]$CommitPush,
  [switch]$Force
)

# --- utils s "approved verbs" ---
function Add-SemicolonIfMissing {
  param([Parameter(Mandatory)][string]$Text)
  $t = $Text.Trim()
  if ($t -notmatch ';$') { return "$t;`n" } else { return "$t`n" }
}

function New-DirectoryIfMissing {
  param([Parameter(Mandatory)][string]$Path)
  if (!(Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Test-RepoChanges {
  param([Parameter(Mandatory)][string]$RepoPath)
  $s = (git -C $RepoPath status --porcelain) 2>$null
  return -not [string]::IsNullOrWhiteSpace($s)
}

function Resolve-PackagePath {
  param(
    [Parameter(Mandatory)][string]$PackagesDir,
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Mode
  )
  $snake = $Table
  $kebab = ($Table -replace '_','-')

  $candidates = switch ($Mode) {
    'snake' { @( Join-Path $PackagesDir $snake ) }
    'kebab' { @( Join-Path $PackagesDir $kebab ) }
    default { @(
      (Join-Path $PackagesDir $snake),
      (Join-Path $PackagesDir $kebab)
    ) }
  }

  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}

# --- načtení mapy ---
if (!(Test-Path -LiteralPath $MapPath)) { throw "Schema map not found at '$MapPath'." }
$map = Import-PowerShellDataFile -Path $MapPath
$tables = $map.Tables.Keys | Sort-Object

$mapLeaf    = Split-Path -Leaf $MapPath
$mapRev     = (git log -1 --format=%h -- $MapPath) 2>$null
$mapRevDate = (git log -1 --date=iso-strict --format=%cd -- $MapPath) 2>$null
if (-not $mapRev) { $mapRev = 'working-tree'; $mapRevDate = (Get-Date).ToString('s') }

foreach ($t in $tables) {
  $pkgPath = Resolve-PackagePath -PackagesDir $PackagesDir -Table $t -Mode $NameResolution
  if (-not $pkgPath) {
    $snake = $t
    $kebab = ($t -replace '_','-')
    Write-Warning "SKIP [$t] – nenalezen submodul. Hledáno: '.\packages\$snake' a '.\packages\$kebab'."
    continue
  }

  $schemaDir = Join-Path $pkgPath 'schema'
  New-DirectoryIfMissing -Path $schemaDir

  $file001 = Join-Path $schemaDir '001_table.sql'
  $file020 = Join-Path $schemaDir '020_indexes.sql'
  $file030 = Join-Path $schemaDir '030_foreign_keys.sql'

  $create  = $map.Tables[$t].create
  $indexes = @($map.Tables[$t].indexes | Where-Object { $_ -and $_.Trim() -ne '' })
  $fks     = @($map.Tables[$t].foreign_keys | Where-Object { $_ -and $_.Trim() -ne '' })

  if (-not $create) { Write-Warning "SKIP [$t] – chybí 'create' v mapě."; continue }

  $header = @"
-- Auto-generated from $mapLeaf @ $mapRev ($mapRevDate)
-- table: $t
"@

  # 001
  $content001 = $header + "`n" + (Add-SemicolonIfMissing $create)
  Set-Content -Path $file001 -Value $content001 -NoNewline -Encoding UTF8

  # 020
  if ($indexes.Count -gt 0 -or $Force) {
    $content020 = $header + "`n" + (($indexes | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
    Set-Content -Path $file020 -Value $content020 -NoNewline -Encoding UTF8
  } elseif (Test-Path -LiteralPath $file020) { Remove-Item -LiteralPath $file020 -Force }

  # 030
  if ($fks.Count -gt 0 -or $Force) {
    $content030 = $header + "`n" + (($fks | ForEach-Object { Add-SemicolonIfMissing $_ }) -join "`n")
    Set-Content -Path $file030 -Value $content030 -NoNewline -Encoding UTF8
  } elseif (Test-Path -LiteralPath $file030) { Remove-Item -LiteralPath $file030 -Force }

  if ($CommitPush) {
    git -C $pkgPath add schema/*.sql | Out-Null
    if (Test-RepoChanges -RepoPath $pkgPath) {
      $branch = (git -C $pkgPath rev-parse --abbrev-ref HEAD).Trim()
      git -C $pkgPath commit -m "chore(schema): update $t (split from umbrella)" | Out-Null
      git -C $pkgPath push origin $branch | Out-Null
      Write-Host "PUSHED [$t] -> $branch"
    } else {
      Write-Host "NO-CHANGE [$t]"
    }
  } else {
    Write-Host "WROTE [$t] -> $schemaDir"
  }
}