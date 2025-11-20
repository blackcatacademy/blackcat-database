param(
  [Parameter(Mandatory=$true)] [string] $ManifestPath,
  [Parameter(Mandatory=$true)] [string] $OutDir,
  [switch] $Check
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$man = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json

function Invoke-ExplainPlan {
  param([string]$sql,[string]$name)
  $php = @'
<?php
$dsn=getenv("DB_DSN"); $user=getenv("DB_USER"); $pass=getenv("DB_PASS");
$db = new PDO($dsn, $user ?: "", $pass ?: "", [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$drv = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
if ($drv === "pgsql") {
  $stmt = $db->query("EXPLAIN (ANALYZE, BUFFERS) ".$_ENV['SQL']);
  echo implode("\n", $stmt->fetchAll(PDO::FETCH_COLUMN));
} else {
  $stmt = $db->query("EXPLAIN ".$_ENV['SQL']);
  echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC), JSON_PRETTY_PRINT);
}
'@
  $env:SQL = $sql
  $tmp = New-TemporaryFile
  Set-Content -Path $tmp -Value $php -NoNewline -Encoding UTF8
  try { $out = & php $tmp } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
  return $out
}

if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$fail = $false
foreach ($q in $man.queries) {
  $sql = $q.sql
  $name = $q.name
  $out = Invoke-ExplainPlan -sql $sql -name $name
  $path = Join-Path $OutDir ($name + ".txt")
  if ($Check -and (Test-Path $path)) {
    $old = Get-Content -Raw -Path $path
    if ($old -ne $out) {
      Write-Host "PLAN_CHANGED: $name"
      $fail = $true
    }
  } else {
    $out | Out-File -FilePath $path -NoNewline -Encoding UTF8
    Write-Host "Wrote $path"
  }
}
if ($Check -and $fail) { exit 1 }
