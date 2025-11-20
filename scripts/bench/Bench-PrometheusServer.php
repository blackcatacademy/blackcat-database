<?php
declare(strict_types=1);

/**
 * Bench-PrometheusServer.php
 *
 * Run:
 *   php -S 0.0.0.0:9101 scripts/bench/Bench-PrometheusServer.php
 *
 * Query:
 *   curl http://localhost:9101/metrics
 *
 * Params (env or query):
 *   CSV_GLOB=/path/prefix_*.csv
 *   DB=mydb
 *   MODE=select
 *   TABLE=bench_items
 */

function envOrGet(string $key, ?string $default=null): ?string {
    $v = getenv($key);
    if ($v !== false && $v !== '') return $v;
    if (isset($_GET[$key])) return (string)$_GET[$key];
    return $default;
}

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($path !== '/metrics') {
    header('Content-Type: text/plain; charset=utf-8');
    echo "# Bench Prometheus server\n";
    echo "# Use /metrics endpoint. Example:\n";
    echo "#   curl 'http://localhost:9101/metrics?CSV_GLOB=./bench/results/*.csv&DB=postgres&MODE=select&TABLE=bench_items'\n";
    exit;
}

$glob = envOrGet('CSV_GLOB', './bench/results/*.csv');
$db   = envOrGet('DB', 'unknown');
$mode = envOrGet('MODE', 'select');
$table= envOrGet('TABLE', 'bench_items');

$files = glob($glob) ?: [];
$histBuckets = [1,2,5,10,20,50,100,200,500,1000,2000];
$hist = array_fill(0, count($histBuckets)+1, 0); // last=+Inf

$ops_total = 0; $ops_err = 0; $lat_sum = 0; $lat_cnt = 0; $rows_total = 0;

foreach ($files as $f) {
    if (!is_readable($f)) continue;
    if (($fh = fopen($f, 'r')) === false) continue;
    $header = fgetcsv($fh);
    if (!$header) { fclose($fh); continue; }
    while (($row = fgetcsv($fh)) !== false) {
        $rec = array_combine($header, $row);
        if (!$rec) continue;
        $ops_total++;
        $ok = (int)($rec['ok'] ?? 0);
        if ($ok !== 1) $ops_err++;
        $ms = (int)($rec['ms'] ?? 0);
        $rows_total += (int)($rec['rows'] ?? 0);
        $lat_sum += $ms; $lat_cnt++;
        $placed = false;
        foreach ($histBuckets as $i => $b) {
            if ($ms <= $b) { $hist[$i]++; $placed = true; break; }
        }
        if (!$placed) { $hist[count($hist)-1]++; }
    }
    fclose($fh);
}

// Output Prometheus text format
header('Content-Type: text/plain; version=0.0.4; charset=utf-8');

function esc($s){ return str_replace(['\\','"'], ['\\\\','\\"'], $s); }

$labels = sprintf('app="blackcat-bench",db="%s",mode="%s",table="%s"', esc($db), esc($mode), esc($table));

echo "# HELP bench_ops_total Total operations\n";
echo "# TYPE bench_ops_total counter\n";
printf("bench_ops_total{%s} %d\n", $labels, $ops_total);

echo "# HELP bench_errors_total Total error operations\n";
echo "# TYPE bench_errors_total counter\n";
printf("bench_errors_total{%s} %d\n", $labels, $ops_err);

echo "# HELP bench_rows_total Total rows processed\n";
echo "# TYPE bench_rows_total counter\n";
printf("bench_rows_total{%s} %d\n", $labels, $rows_total);

echo "# HELP bench_latency_ms Latency histogram (ms)\n";
echo "# TYPE bench_latency_ms histogram\n";
$cum = 0;
foreach ($histBuckets as $i => $b) {
    $cum += $hist[$i];
    printf('bench_latency_ms_bucket{%s,le="%s"} %d' . "\n", $labels, (string)$b, $cum);
}
$cum += $hist[count($hist)-1];
printf('bench_latency_ms_bucket{%s,le="+Inf"} %d' . "\n", $labels, $cum);
printf("bench_latency_ms_sum{%s} %d\n", $labels, $lat_sum);
printf("bench_latency_ms_count{%s} %d\n", $labels, $lat_cnt);
