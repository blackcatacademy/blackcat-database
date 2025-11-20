param(
  [Parameter(Mandatory=$true)] [string] $PackagesDir,
  [Parameter(Mandatory=$true)] [string] $MapPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "../support/SqlDocUtils.psm1") -Force

# Expect DB creds via env: DB_DSN, DB_USER, DB_PASS
function Get-DbSchema {
  $php = @'
<?php
$dsn = getenv("DB_DSN"); $user=getenv("DB_USER"); $pass=getenv("DB_PASS");
if (!$dsn) { fwrite(STDERR,"DB_DSN missing\n"); exit(2); }
$db = new PDO($dsn, $user ?: "", $pass ?: "", [
  PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
  PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC
]);
$driver = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
$out = [];
if ($driver === "pgsql") {
  $q = "SELECT table_name, column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name, ordinal_position";
  $rows = $db->query($q)->fetchAll();
  foreach ($rows as $r) {
    $t = $r['table_name'];
    $out[$t]['columns'][] = [$r['column_name'], $r['data_type'], $r['is_nullable']];
  }
} else { # mysql/mariadb
  $dbName = $db->query("select database()")->fetchColumn();
  $q = "SELECT table_name, column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = ".$db->quote($dbName)." ORDER BY table_name, ordinal_position";
  $rows = $db->query($q)->fetchAll();
  foreach ($rows as $r) {
    $t = $r['table_name'];
    $out[$t]['columns'][] = [$r['column_name'], $r['data_type'], $r['is_nullable']];
  }
}
echo json_encode(['driver'=>$driver, 'schema'=>$out]);
'@
  $tmp = New-TemporaryFile
  Set-Content -Path $tmp -Value $php -NoNewline -Encoding UTF8
  try {
    $json = & php $tmp
  } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
  if (-not $json) { throw "Failed to get DB schema" }
  return $json | ConvertFrom-Json
}

$map = Import-PowerShellDataFile -Path $MapPath
$db = Get-DbSchema

$diffs = @()
foreach ($key in $map.Keys) {
  $m = $map[$key]
  $pkgDir = Join-Path $PackagesDir $m.Package
  $schemaFiles = Get-ChildItem -Path (Join-Path $pkgDir 'schema') -Filter *.sql -Recurse -File -ErrorAction SilentlyContinue
  if (-not $schemaFiles) { continue }
  $sql = Get-Content -Raw -Path ($schemaFiles | Select-Object -Expand FullName)
  $norm = Format-SqlText -Sql $sql
  $blocks = Get-TableBlocks -Sql $norm
  $b = $blocks | Where-Object { $_.Table -eq $m.Table } | Select-Object -First 1
  if (-not $b) { continue }
  $colsExp = Get-ColumnMetadata -Body $b.Body | ForEach-Object { "$($_.Name)|$($_.Type)|$($_.Nullable)" }

  # DB actual
  if (-not $db.schema.ContainsKey($m.Table)) {
    $diffs += "MISSING_ON_DB: $($m.Table)"
    continue
  }
  $colsDb = @()
  foreach ($c in $db.schema[$m.Table].columns) {
    $colsDb += ($c[0] + "|" + $c[1] + "|" + $c[2])
  }

  $missing = Compare-Object -ReferenceObject $colsExp -DifferenceObject $colsDb -PassThru | Where-Object { $_ -in $colsExp }
  $extra   = Compare-Object -ReferenceObject $colsExp -DifferenceObject $colsDb -PassThru | Where-Object { $_ -in $colsDb }
  if ($missing -or $extra) {
    $diffs += "DRIFT_COLUMNS: $($m.Table)"
    if ($missing) { $diffs += "  expected_not_on_db: " + ($missing -join ", ") }
    if ($extra)   { $diffs += "  db_not_in_expected: " + ($extra -join ", ") }
  }
}

if ($diffs.Count -gt 0) {
  Write-Host "# Schema Drift Report"
  $diffs | ForEach-Object { Write-Host $_ }
  exit 1
} else {
  Write-Host "No schema drift detected."
}
