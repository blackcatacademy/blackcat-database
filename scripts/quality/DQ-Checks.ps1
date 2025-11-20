param(
  [Parameter(Mandatory=$true)] [string] $DbDsn,
  [string] $DbUser = "",
  [string] $DbPass = "",
  [Parameter(Mandatory=$true)] [string] $OutPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$php = @'
<?php
$dsn=$_ENV["DSN"]; $user=$_ENV["USR"]; $pass=$_ENV["PWD"];
$db = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$driver = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
$issues = [];

// Example scans (add more as needed)
function check_orphans($db, $table, $col, $refTable, $refCol) {
  $sql = "SELECT COUNT(*) FROM $table t LEFT JOIN $refTable r ON t.$col = r.$refCol WHERE r.$refCol IS NULL";
  $c = (int)$db->query($sql)->fetchColumn();
  return [$sql, $c];
}

list($sql1,$c1) = check_orphans($db, "orders", "user_id", "users", "id");
if ($c1>0) $issues[] = ["orphan_orders_user_id", $sql1, $c1];

echo json_encode(["ok"=>count($issues)==0, "issues"=>$issues]);
'@

$env:DSN=$DbDsn; $env:USR=$DbUser; $env:PWD=$DbPass
$tmp = New-TemporaryFile
Set-Content -Path $tmp -Value $php -NoNewline -Encoding UTF8
try { $json = & php $tmp } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
($json | ConvertFrom-Json) | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutPath -NoNewline -Encoding UTF8
Write-Host "Wrote $OutPath"
