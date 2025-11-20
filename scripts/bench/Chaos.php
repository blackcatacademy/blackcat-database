<?php
declare(strict_types=1);
$options = getopt("", ["dsn:", "user::", "pass::", "action:", "table::"]);
$dsn = $options["dsn"] ?? getenv("DB_DSN") ?: "";
$user = $options["user"] ?? getenv("DB_USER") ?: "";
$pass = $options["pass"] ?? getenv("DB_PASS") ?: "";
$action = strtolower($options["action"] ?? "lock");
$table = $options["table"] ?? "bench_items";
if (!$dsn) { fwrite(STDERR, "Missing --dsn\n"); exit(2); }
$table = sanitize_identifier($table);
$db = new PDO($dsn, $user, $pass, [
  PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
  PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
$drv = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
function sanitize_identifier(string $identifier): string {
  if (!preg_match('/^[A-Za-z0-9_]+$/', $identifier)) {
    throw new InvalidArgumentException("Unsafe identifier supplied: {$identifier}");
  }
  return $identifier;
}
function quote_identifier(string $identifier, string $driver): string {
  return $driver === 'pgsql' ? '"' . $identifier . '"' : '`' . $identifier . '`';
}
function ensure_table(PDO $db, string $drv, string $table): void {
  $qt = quote_identifier($table, $drv);
  if ($drv === 'pgsql') {
    $db->exec("CREATE TABLE IF NOT EXISTS $qt (id BIGSERIAL PRIMARY KEY, v INT NOT NULL DEFAULT 0)");
  } else {
    $db->exec("CREATE TABLE IF NOT EXISTS $qt (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, v INT NOT NULL DEFAULT 0) ENGINE=InnoDB");
  }
  $db->exec("INSERT INTO $qt (v) SELECT 0 WHERE NOT EXISTS (SELECT 1 FROM $qt)");
}
ensure_table($db, $drv, $table);
$qt = quote_identifier($table, $drv);
if ($action === 'lock') {
  $db->beginTransaction();
  $db->exec("UPDATE $qt SET v = v + 1 WHERE id = (SELECT MIN(id) FROM $qt)");
  $db2 = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
  try {
    if ($drv === 'pgsql') {
      $db2->exec("SET LOCAL lock_timeout='100ms'");
      $db2->exec("UPDATE $qt SET v = v + 1 WHERE id = (SELECT MIN(id) FROM $qt)");
    } else {
      $db2->exec("SET innodb_lock_wait_timeout=1");
      $db2->exec("UPDATE $qt SET v = v + 1 WHERE id = (SELECT MIN(id) FROM $qt)");
    }
    echo "LOCK_SECOND_SUCCEEDED\n";
  } catch (Throwable $e) {
    echo "LOCK_TIMEOUT_OK\n";
  }
  $db->rollBack();
  exit(0);
}
if ($action === 'kill') {
  if ($drv !== 'pgsql') { echo "KILL_ONLY_PG\n"; exit(0); }
  $pid = (int)$db->query("SELECT pg_backend_pid()")->fetchColumn();
  $ok = $db->query("SELECT pg_terminate_backend($pid)")->fetchColumn();
  echo "TERMINATE_SELF=".(int)$ok."\n";
  try { $db->query("SELECT 1")->fetchColumn(); echo "STILL_ALIVE\n"; } catch (Throwable $e) { echo "KILLED_OK\n"; }
  exit(0);
}
echo "UNKNOWN_ACTION\n";
