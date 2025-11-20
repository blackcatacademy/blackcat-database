param(
  [Parameter(Mandatory=$true)] [string[]] $SqlPaths,
  [int] $LockTimeoutMs = 2000
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Risky tokens heuristic
$risky = @('DROP TABLE','DROP COLUMN','ALTER TYPE','ALTER TABLE .* DROP','TRUNCATE','RENAME COLUMN')
$danger = @()

foreach ($p in $SqlPaths) {
  if (!(Test-Path $p)) { throw "Not found: $p" }
  $sql = Get-Content -Raw -Path $p
  foreach ($pat in $risky) {
    if ($sql -match $pat) { $danger += "[WARN] Risky token in $($p): $pat" }
  }
}

if ($danger.Count -gt 0) { $danger | ForEach-Object { Write-Warning $_ } }

# Use PHP+PDO for a transactional dry-run followed by ROLLBACK
$php = @'
<?php
$dsn = getenv("DB_DSN"); $user=getenv("DB_USER"); $pass=getenv("DB_PASS");
if (!$dsn) { fwrite(STDERR,"DB_DSN missing\n"); exit(2); }
$db = new PDO($dsn, $user ?: "", $pass ?: "", [
  PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
  PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC
]);
$driver = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
$sqls = json_decode(getenv("SQLS"), true);
$db->beginTransaction();
try {
  if ($driver === "pgsql") {
    $db->exec("SET LOCAL lock_timeout = ".(int)(getenv('LOCK_MS')?:2000));
  }
  foreach ($sqls as $s) {
    $db->exec($s);
  }
  $db->rollBack(); // dry-run
  echo "OK";
} catch (Throwable $e) {
  $db->rollBack();
  fwrite(STDERR, "ERR: ".$e->getMessage());
  exit(1);
}
'@

$payload = @()
foreach ($p in $SqlPaths) {
  $payload += (Get-Content -Raw -Path $p)
}
$env:SQLS = ($payload | ConvertTo-Json -Depth 4)
$env:LOCK_MS = "$LockTimeoutMs"
$tmp = New-TemporaryFile
Set-Content -Path $tmp -Value $php -NoNewline -Encoding UTF8
try {
  & php $tmp
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
