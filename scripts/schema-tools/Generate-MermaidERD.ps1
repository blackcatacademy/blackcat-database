param(
  [Parameter(Mandatory=$true)] [string] $PackagesDir,
  [Parameter(Mandatory=$true)] [string] $MapPath,
  [Parameter(Mandatory=$true)] [string] $OutPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "../support/SqlDocUtils.psm1") -Force

$map = Import-PowerShellDataFile -Path $MapPath

$lines = @("```mermaid","erDiagram")

$tables = @{}
$rels = @()

foreach ($key in $map.Keys) {
  $m = $map[$key]
  $pkgDir = Join-Path $PackagesDir $m.Package
  if (!(Test-Path $pkgDir)) { continue }

  $sql = Format-SqlText -Sql (Get-FileText -Files ((Get-SqlFiles -Dir (Join-Path $pkgDir 'schema')) + (Get-SqlFiles -Dir (Join-Path $pkgDir 'views'))))
  $tblBlocks = Get-TableBlocks -Sql $sql
  $tbl = $tblBlocks | Where-Object { $_.Table -eq $m.Table } | Select-Object -First 1
  if (-not $tbl) { continue }

  $cols = Get-ColumnMetadata -Body $tbl.Body
  $tables[$m.Table] = $cols

  $fks  = Get-ForeignKeyMetadata -Sql $sql -Table $m.Table
  foreach ($fk in $fks) {
    if ($fk.References -match '^(?<rt>[\w\.]+)\((?<rc>[^\)]+)\)') {
      $rt = $matches['rt']
      $rels += "$($m.Table) }o--|| $rt : $($fk.Name)"
    }
  }
}

foreach ($t in $tables.Keys) {
  $lines += ("  " + $t + " {")
  foreach ($c in $tables[$t]) {
    $lines += ("    " + $c.Type + " " + $c.Name)
  }
  $lines += "  }"
}
$lines += $rels | Sort-Object -Unique
$lines += "```"

$lines -join "`n" | Out-File -FilePath $OutPath -NoNewline -Encoding UTF8
Write-Host "Wrote $OutPath"
