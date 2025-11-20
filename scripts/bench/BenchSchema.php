<?php
declare(strict_types=1);

$options = getopt("", ["dsn:", "user::", "pass::", "table::", "seed::"]);
$dsn = $options["dsn"] ?? getenv("DB_DSN") ?: "";
$user = $options["user"] ?? getenv("DB_USER") ?: "";
$pass = $options["pass"] ?? getenv("DB_PASS") ?: "";
$table = $options["table"] ?? "bench_items";
$seed = (int)($options["seed"] ?? 50000);
if (!$dsn) { fwrite(STDERR, "Missing --dsn\n"); exit(2); }

$db = new PDO($dsn, $user, $pass, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);

$drv = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
$quoteIdent = function(string $n) use ($drv): string {
    if ($drv === 'pgsql') return '"' . str_replace('"','""',$n) . '"';
    return '`' . str_replace('`','``',$n) . '`';
};

$tn = $table;
$qt = $quoteIdent($tn);

// Create table if not exists
if ($drv === 'pgsql') {
    $db->exec("CREATE TABLE IF NOT EXISTS $qt (
        id BIGSERIAL PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        title TEXT NOT NULL,
        deleted_at TIMESTAMPTZ NULL
    )");
    $db->exec("CREATE INDEX IF NOT EXISTS idx_{$tn}_created_id ON $qt (created_at DESC, id DESC)");
    $db->exec("CREATE UNIQUE INDEX IF NOT EXISTS ux_{$tn}_title ON $qt (title)");
} else { // mysql/mariadb
    $db->exec("CREATE TABLE IF NOT EXISTS $qt (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        title TEXT NOT NULL,
        deleted_at TIMESTAMP NULL DEFAULT NULL
    ) ENGINE=InnoDB");
    $db->exec("CREATE INDEX idx_{$tn}_created_id ON $qt (created_at DESC, id DESC)");
    // TEXT cannot be unique in MySQL without prefix; switch to VARCHAR
    try { $db->exec("ALTER TABLE $qt MODIFY title VARCHAR(255) NOT NULL"); } catch (\Throwable $e) {}
    $db->exec("CREATE UNIQUE INDEX ux_{$tn}_title ON $qt (title)");
}

// Count and seed
$cnt = (int)$db->query("SELECT COUNT(*) FROM $qt")->fetchColumn();
$need = max(0, $seed - $cnt);
if ($need > 0) {
    $db->beginTransaction();
    try {
        $ins = $db->prepare("INSERT INTO $qt (created_at, title) VALUES (?, ?)");
        $now = time();
        for ($i=0; $i<$need; $i++) {
            $ts = date(($drv==='pgsql') ? 'c' : 'Y-m-d H:i:s', $now - random_int(0, 86400*30));
            $title = sprintf("seed-%06d-%s", $cnt + $i + 1, bin2hex(random_bytes(3)));
            $ins->execute([$ts, $title]);
            if (($i+1) % 1000 === 0) { /* commit chunks to avoid huge tx */ $db->commit(); $db->beginTransaction(); }
        }
        $db->commit();
    } catch (\Throwable $e) {
        $db->rollBack();
        fwrite(STDERR, "Seed failed: ".$e->getMessage()."\n");
        exit(1);
    }
}

echo "Table: $tn, rows: ".(int)$db->query("SELECT COUNT(*) FROM $qt")->fetchColumn()."\n";
