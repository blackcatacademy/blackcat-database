param(
  [Parameter(Mandatory=$true)] [string] $PackagesDir,
  [Parameter(Mandatory=$true)] [string] $MapPath,
  [string] $RulesPath = "$PSScriptRoot/SqlLintRules.psd1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "../support/SqlDocUtils.psm1") -Force
$rules = Import-PowerShellDataFile -Path $RulesPath
$map   = Import-PowerShellDataFile -Path $MapPath

$failCount = 0
$warnCount = 0
$items = @()

function Test-IndexForColumns {
  param([object[]]$Indexes, [string[]]$Cols)
  foreach ($ix in $Indexes) {
    $ixCols = ($ix.Columns -split ',\s*')
    if (@(Compare-Object -ReferenceObject $Cols -DifferenceObject $ixCols -IncludeEqual:$false -ExcludeDifferent:$true).Count -eq 0) {
      return $true
    }
  }
  # Fallback: any index whose prefix matches FK columns order
  foreach ($ix in $Indexes) {
    $ixCols = ($ix.Columns -split ',\s*')
    if ($ixCols.Count -ge $Cols.Count -and @($ixCols[0..($Cols.Count-1)] -ceq $Cols).Count -eq $Cols.Count) {
      return $true
    }
  }
  return $false
}

foreach ($key in $map.Keys) {
  $m = $map[$key]
  $pkgDir = Join-Path $PackagesDir $m.Package
  if (!(Test-Path $pkgDir)) { Write-Warning "Missing $pkgDir"; continue }

  $schema = Get-FileText -Files (Get-SqlFiles -Dir (Join-Path $pkgDir 'schema'))
  $views  = Get-FileText -Files (Get-SqlFiles -Dir (Join-Path $pkgDir 'views'))
  $allSql = Format-SqlText -Sql ($schema + "`n" + $views)

  $tblocks = Get-TableBlocks -Sql $allSql
  $tbl = $tblocks | Where-Object { $_.Table -eq $m.Table } | Select-Object -First 1
  if (-not $tbl) { continue }
  $cols = Get-ColumnMetadata -Body $tbl.Body
  $pk   = Get-PrimaryKeyInfo -Body $tbl.Body
  $idx  = Get-IndexMetadata -Sql $allSql -Table $m.Table
  $fks  = Get-ForeignKeyMetadata -Sql $allSql -Table $m.Table
  $viewsList = Get-ViewNames -Sql $allSql

  # Rule: PK required
  if ($rules.RequirePrimaryKey -and -not $pk) {
    $failCount++
    $items += "FAIL [$($m.Package)]: table `$($m.Table)` has no PRIMARY KEY"
  }

  # Rule: Each FK must have an index on referencing columns
  if ($rules.RequireFkIndex -and $fks.Count -gt 0) {
    foreach ($fk in $fks) {
      $refCols = ($fk.Columns -split ',\s*')
      if (-not (Test-IndexForColumns -Indexes $idx -Cols $refCols)) {
        $failCount++
        $items += "FAIL [$($m.Package)]: FK `$($fk.Name)` missing index on ($($fk.Columns))"
      }
    }
  }

  # View directives (only check when views exist; SQL dialect inference is outside scope)
  if ($rules.RequireViewDirectives -and $viewsList.Count -gt 0) {
    # If any view file exists under views/, require tokens ALGORITHM= and SQL SECURITY
    $rawViews = Get-FileText -Files (Get-SqlFiles -Dir (Join-Path $pkgDir 'views'))
    if ($rawViews -notmatch 'ALGORITHM\s*=' -or $rawViews -notmatch 'SQL\s+SECURITY\s+(DEFINER|INVOKER)') {
      $warnCount++
      $items += "WARN [$($m.Package)]: views/*.sql missing ALGORITHM and/or SQL SECURITY directives (required on MySQL/MariaDB)"
    }
  }

  # Time columns recommendation
  $tc = $rules.TimeColumns
  $hasTime = $false
  foreach ($c in $cols) {
    if ($tc -contains ($c.Name.ToLower())) { $hasTime = $true; break }
  }
  if (-not $hasTime) {
    $warnCount++
    $items += "WARN [$($m.Package)]: consider adding created_at/updated_at timestamps"
  }
}

if ($items.Count -gt 0) { $items | ForEach-Object { Write-Host $_ } }
Write-Host "----"
Write-Host "Summary: FAIL=$failCount, WARN=$warnCount"
if ($failCount -gt 0) { exit 1 } else { exit 0 }
