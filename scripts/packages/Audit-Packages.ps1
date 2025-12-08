param(
  [string] $PackagesDir = 'packages',
  [string] $MapPath = 'scripts/schema/schema-map-postgres.yaml',
  [string] $ViewsLibraryRoot = 'views-library',
  [string] $OutPath = 'docs/AUDIT.md',
  [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "../support/SqlDocUtils.psm1") -Force

if (-not (Test-Path -LiteralPath $MapPath)) { throw "Map not found: $MapPath" }
if (-not (Test-Path -LiteralPath $PackagesDir)) { throw "PackagesDir not found: $PackagesDir" }

$map = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Yaml
$tables = $map.Tables.Keys | Sort-Object

$rows = @()
$total = @{
  Packages=0; Tables=0; Indexes=0; FKs=0; Views=0; WithPK=0; WithTime=0; UniqueIdx=0
}

function Test-TimeColumn {
  param($cols)
  $names = @('created_at','updated_at','createdon','updatedon','timestamp','ts')
  foreach ($c in $cols) { if ($names -contains ($c.Name.ToLower())) { return $true } }
  return $false
}

function Measure-TableScore {
  param($hasPk,$hasTime,$uniqueCount,$fkCount,$viewCount,$missingFkIdx)
  $score = 0
  if ($hasPk)   { $score += 40 }
  if ($hasTime) { $score += 10 }
  if ($uniqueCount -gt 0) { $score += 10 }
  if ($fkCount -gt 0)     { $score += 10 }
  if (-not $missingFkIdx) { $score += 10 }
  if ($viewCount -gt 0)   { $score += 10 }
  return $score
}

function Test-IndexForColumns {
  param([object[]]$Indexes, [string[]]$Cols)
  foreach ($ix in $Indexes) {
    $ixCols = ($ix.Columns -split ',\s*')
    if (@(Compare-Object -ReferenceObject $Cols -DifferenceObject $ixCols -IncludeEqual:$false -ExcludeDifferent:$true).Count -eq 0) {
      return $true
    }
  }
  foreach ($ix in $Indexes) {
    $ixCols = ($ix.Columns -split ',\s*')
    if ($ixCols.Count -ge $Cols.Count -and @($ixCols[0..($Cols.Count-1)] -ceq $Cols).Count -eq $Cols.Count) {
      return $true
    }
  }
  return $false
}

foreach ($tableName in $tables) {
  $pkgSlug = ($tableName -replace '_','-')
  $pkgDir = Join-Path $PackagesDir $pkgSlug

  $schemaDir = Join-Path $pkgDir 'schema'
  $viewDirs = @()
  $viewDirPkg = Join-Path $pkgDir 'views'
  if (Test-Path -LiteralPath $viewDirPkg) { $viewDirs += $viewDirPkg }
  if ($ViewsLibraryRoot) {
    $viewLib = Join-Path $ViewsLibraryRoot $pkgSlug
    if (Test-Path -LiteralPath $viewLib) { $viewDirs += $viewLib }
  }

  if (-not (Test-Path -LiteralPath $pkgDir) -and $viewDirs.Count -eq 0) {
    Write-Warning "Missing package folder and views for $tableName ($pkgDir)"; continue
  }

  $schema = @()
  if (Test-Path -LiteralPath $schemaDir) {
    $schema = Get-FileText -Files (Get-SqlFiles -Dir $schemaDir)
  }
  $views  = @()
  foreach ($vd in $viewDirs) {
    $views += Get-FileText -Files (Get-SqlFiles -Dir $vd)
  }
  $allSql = Format-SqlText -Sql (($schema + $views) -join "`n")

  $tblBlocks = Get-TableBlocks -Sql $allSql
  $tbl = $tblBlocks | Where-Object { $_.Table -eq $tableName } | Select-Object -First 1
  if (-not $tbl) { continue }

  $cols = @(Get-ColumnMetadata -Body $tbl.Body)
  $pk   = Get-PrimaryKeyInfo -Body $tbl.Body
  $idx  = @(Get-IndexMetadata -Sql $allSql -Table $tableName)
  $fks  = @(Get-ForeignKeyMetadata -Sql $allSql -Table $tableName)
  $vws  = @(Get-ViewNames -Sql $allSql)

  $hasPk = [bool]$pk
  $hasTime = Test-TimeColumn $cols
  $uniqueCount = (@($idx | Where-Object { $_.Unique })).Count
  $missingFkIdx = $false
  foreach ($fk in $fks) {
    $refCols = ($fk.Columns -split ',\s*')
    if (-not (Test-IndexForColumns -Indexes $idx -Cols $refCols)) { $missingFkIdx = $true; break }
  }

  $score = Measure-TableScore $hasPk $hasTime $uniqueCount $fks.Count $vws.Count $missingFkIdx

  $rows += "| [$pkgSlug](./packages/$pkgSlug) | `$tableName` | $($cols.Count) | $($idx.Count) | $($uniqueCount) | $($fks.Count) | $($vws.Count) | $hasPk | $hasTime | $([bool](-not $missingFkIdx)) | $score |"

  $total.Packages++
  $total.Tables++
  $total.Indexes += $idx.Count
  $total.FKs     += $fks.Count
  $total.Views   += $vws.Count
  if ($hasPk)   { $total.WithPK++ }
  if ($hasTime) { $total.WithTime++ }
  if ($uniqueCount -gt 0) { $total.UniqueIdx++ }
}

$md = @"
# Database Audit Report

| Package | Table | Columns | Indexes | UniqueIdx | FKs | Views | HasPK | HasTime | FKIndexed | Score |
|---|---:|---:|---:|---:|---:|---:|:---:|:---:|:---:|---:|
$($rows -join "`n")

**Totals:** packages=$($total.Packages), tables=$($total.Tables), indexes=$($total.Indexes), FKs=$($total.FKs), views=$($total.Views), withPK=$($total.WithPK), withTime=$($total.WithTime), withUnique=$($total.UniqueIdx)

> Score formula: PK(40) + Time(10) + UniqueIdx(10) + FK(10) + FKIndexed(10) + Views(10)
"@

$outDir = Split-Path -Parent $OutPath
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$md | Out-File -FilePath $OutPath -NoNewline -Encoding UTF8
Write-Host "Wrote $OutPath"
