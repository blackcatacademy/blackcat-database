<?php
declare(strict_types=1);
$options = getopt("", ["dsn:", "user::", "pass::", "variants::", "out::"]);
$dsn = $options["dsn"] ?? getenv("DB_DSN") ?: "";
$user = $options["user"] ?? getenv("DB_USER") ?: "";
$pass = $options["pass"] ?? getenv("DB_PASS") ?: "";
$out = $options["out"] ?? "tls";
$variants = $options["variants"] ?? "disable,allow,prefer,require,verify-ca,verify-full";
if (!$dsn) { fwrite(STDERR, "Missing --dsn\n"); exit(2); }
if (strpos($dsn, 'pgsql:') !== 0) { fwrite(STDERR, "Currently supports pgsql only.\n"); exit(0); }
@mkdir($out, 0777, true);
$res = [];
foreach (explode(',', $variants) as $mode) {
  $mode = trim($mode);
  $testDsn = $dsn . (str_contains($dsn,';') ? ';' : '') . "sslmode=$mode";
  $ok = false; $err = '';
  try {
    $db = new PDO($testDsn, $user, $pass, [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
    $db->query("SELECT version()")->fetchColumn();
    $ok = true;
  } catch (\Throwable $e) { $ok = false; $err = $e->getMessage(); }
  $res[] = ['sslmode'=>$mode, 'ok'=>$ok, 'error'=>$err];
}
file_put_contents("$out/matrix.json", json_encode($res, JSON_PRETTY_PRINT));
$bad = array_values(array_filter($res, fn($r)=>!$r['ok'] && in_array($r['sslmode'], ['require','verify-ca','verify-full'], true)));
echo count($bad) > 0 ? "INSECURE_ONLY\n" : "SECURE_OK\n";
