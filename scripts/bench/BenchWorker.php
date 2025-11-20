<?php
declare(strict_types=1);

$options = getopt("", ["dsn:", "user::", "pass::", "mode::", "table::", "duration::", "page::", "out:"]);
$dsn = $options["dsn"] ?? getenv("DB_DSN") ?: "";
$user = $options["user"] ?? getenv("DB_USER") ?: "";
$pass = $options["pass"] ?? getenv("DB_PASS") ?: "";
$mode = strtolower($options["mode"] ?? "select");
$table = $options["table"] ?? "bench_items";
$duration = (int)($options["duration"] ?? 30);
$page = max(1, (int)($options["page"] ?? 50));
$out = $options["out"] ?? null;

if (!$dsn || !$out) { fwrite(STDERR, "Missing --dsn or --out\n"); exit(2); }

$db = new PDO($dsn, $user, $pass, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);

$drv = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
$quoteIdent = function(string $n) use ($drv): string {
    if ($drv === 'pgsql') return '"' . str_replace('"','""',$n) . '"';
    return '`' . str_replace('`','``',$n) . '`';
};
$qt = $quoteIdent($table);

function now_ms(): float {
    [$usec, $sec] = explode(" ", microtime());
    return ((float)$usec + (float)$sec) * 1000.0;
}

$end = microtime(true) + $duration;
$iter = 0;
$cursorTs = null; $cursorId = null;

if ($mode === 'seek') {
    // Start at "top" of the keyset (most recent)
    $r = $db->query("SELECT created_at, id FROM $qt ORDER BY created_at DESC, id DESC LIMIT 1")->fetch();
    if ($r) { $cursorTs = $r['created_at']; $cursorId = (int)$r['id']; }
}

$fh = fopen($out, 'a');
if (!$fh) { fwrite(STDERR, "Cannot open out file\n"); exit(3); }

while (microtime(true) < $end) {
    $iter++;
    $t0 = now_ms();
    $ok = 1; $rows = 0;
    try {
        if ($mode === 'seek') {
            if ($drv === 'pgsql') {
                $sql = "SELECT id, created_at FROM $qt WHERE (created_at < :ts) OR (created_at = :ts AND id < :id) ORDER BY created_at DESC, id DESC LIMIT $page";
            } else {
                $sql = "SELECT id, created_at FROM $qt WHERE (created_at < :ts) OR (created_at = :ts AND id < :id) ORDER BY created_at DESC, id DESC LIMIT $page";
            }
            $stmt = $db->prepare($sql);
            $stmt->execute([":ts"=>$cursorTs, ":id"=>$cursorId]);
            $res = $stmt->fetchAll();
            $rows = count($res);
            if ($rows > 0) {
                $last = end($res);
                $cursorTs = $last['created_at'];
                $cursorId = (int)$last['id'];
            } else {
                // wrap around
                $r = $db->query("SELECT created_at, id FROM $qt ORDER BY created_at DESC, id DESC LIMIT 1")->fetch();
                if ($r) { $cursorTs = $r['created_at']; $cursorId = (int)$r['id']; }
            }
        } else { // 'select' default: simple recent page by offset (tiny), then random jump
            $off = random_int(0, 1000);
            $sql = "SELECT id, created_at FROM $qt ORDER BY created_at DESC, id DESC LIMIT $page OFFSET $off";
            if ($drv !== 'pgsql') {
                // MySQL/MariaDB: OFFSET syntax OK since 8.0/10.4. For older: LIMIT off,page.
                $sql = "SELECT id, created_at FROM $qt ORDER BY created_at DESC, id DESC LIMIT $off, $page";
            }
            $res = $db->query($sql)->fetchAll();
            $rows = count($res);
        }
    } catch (\Throwable $e) {
        $ok = 0;
    }
    $ms = (int)round(now_ms() - $t0);
    fputcsv($fh, [$iter, $ms, $ok, $rows]);
}
fclose($fh);
