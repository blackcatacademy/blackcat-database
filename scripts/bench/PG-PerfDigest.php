<?php
declare(strict_types=1);
$options = getopt("", ["dsn:", "user::", "pass::", "out::", "limit::"]);
$dsn = $options["dsn"] ?? getenv("DB_DSN") ?: "";
$user = $options["user"] ?? getenv("DB_USER") ?: "";
$pass = $options["pass"] ?? getenv("DB_PASS") ?: "";
$out  = $options["out"] ?? "perf";
$limit = (int)($options["limit"] ?? 30);
if (!$dsn) { fwrite(STDERR, "Missing --dsn\n"); exit(2); }
$db = new PDO($dsn, $user, $pass, [
  PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
  PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
if ($db->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'pgsql') { fwrite(STDERR, "PG only.\n"); exit(3); }
$db->exec("CREATE EXTENSION IF NOT EXISTS pg_stat_statements");
$q = $db->query("
  SELECT queryid, calls, total_time, mean_time, stddev_time, rows, shared_blks_hit, shared_blks_read,
         temp_blks_written, left(regexp_replace(query, '\s+', ' ', 'g'), 500) AS query
  FROM pg_stat_statements
  WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  ORDER BY total_time DESC
  LIMIT $limit
");
$rows = $q->fetchAll();
@mkdir($out, 0777, true);
file_put_contents("$out/digest.json", json_encode($rows, JSON_PRETTY_PRINT));
$md = "# PG Perf Digest\n\n";
$md .= "| rank | calls | total_ms | mean_ms | rows | query (truncated) |\n|---:|---:|---:|---:|---:|---|\n";
$rank = 1;
foreach ($rows as $r) {
  $md .= sprintf("| %d | %d | %0.0f | %0.2f | %d | %s |\n",
    $rank++, $r['calls'], $r['total_time'], $r['mean_time'], $r['rows'], str_replace("|","\\|",$r['query']));
}
file_put_contents("$out/digest.md", $md);
echo "Wrote $out/digest.json and $out/digest.md\n";
