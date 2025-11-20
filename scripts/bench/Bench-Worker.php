#!/usr/bin/env php
<?php
declare(strict_types=1);

/**
 * Bench-Worker.php
 * Synthetic DB workload generator (SELECT / UPSERT / SEEK).
 *
 * Usage:
 *   php scripts/bench/Bench-Worker.php --mode=select --dsn="pgsql:host=127.0.0.1;port=5432;dbname=testdb" --user=postgres --pass=postgres --table=bench_items --duration=30 --out=worker1.csv
 */

function args(): array {
    $opts = getopt('', [
        'mode:','dsn:','user:','pass:','table::','duration::','sleepMs::','out::',
        'seed::'
    ]);
    $opts['mode'] = strtolower($opts['mode'] ?? 'select');
    $opts['table'] = $opts['table'] ?? 'bench_items';
    $opts['duration'] = (int)($opts['duration'] ?? 30);
    $opts['sleepMs'] = (int)($opts['sleepMs'] ?? 0);
    $opts['seed'] = (int)($opts['seed'] ?? 12345);
    return $opts;
}

function connect(string $dsn, string $user, string $pass): PDO {
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
    return $pdo;
}

function isPg(PDO $db): bool {
    return str_starts_with($db->getAttribute(PDO::ATTR_DRIVER_NAME), 'pgsql');
}

function sanitizeIdentifier(string $identifier): string {
    if (!preg_match('/^[A-Za-z0-9_]+$/', $identifier)) {
        throw new InvalidArgumentException("Unsafe identifier supplied: {$identifier}");
    }
    return $identifier;
}

function quoteIdentifier(PDO $db, string $identifier): string {
    $clean = sanitizeIdentifier($identifier);
    return isPg($db) ? '"' . $clean . '"' : '`' . $clean . '`';
}

function ensureSchema(PDO $db, string $table): void {
    $qt = quoteIdentifier($db, $table);
    if (isPg($db)) {
        $db->exec("CREATE TABLE IF NOT EXISTS {$qt} (
            id BIGSERIAL PRIMARY KEY,
            name TEXT,
            email TEXT UNIQUE,
            v INT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )");
    } else {
        $db->exec("CREATE TABLE IF NOT EXISTS {$qt} (
            id BIGINT PRIMARY KEY AUTO_INCREMENT,
            name VARCHAR(190),
            email VARCHAR(190) UNIQUE,
            v INT,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )");
    }
}

function upsert(PDO $db, string $table, array $row): void {
    $qt = quoteIdentifier($db, $table);
    if (isPg($db)) {
        $sql = "INSERT INTO {$qt} (name,email,v,created_at)
                VALUES (:name,:email,:v,NOW())
                ON CONFLICT (email) DO UPDATE SET
                  name=EXCLUDED.name,
                  v=EXCLUDED.v,
                  created_at=NOW()";
    } else {
        $sql = "INSERT INTO {$qt} (name,email,v,created_at)
                VALUES (:name,:email,:v,CURRENT_TIMESTAMP)
                ON DUPLICATE KEY UPDATE
                  name=VALUES(name), v=VALUES(v), created_at=CURRENT_TIMESTAMP";
    }
    $db->prepare($sql)->execute([
        ':name'=>$row['name'],
        ':email'=>$row['email'],
        ':v'=>$row['v'],
    ]);
}

function selectRecent(PDO $db, string $table): int {
    $qt = quoteIdentifier($db, $table);
    $stmt = $db->query("SELECT id,created_at FROM {$qt} ORDER BY created_at DESC, id DESC LIMIT 50");
    $rows = $stmt->fetchAll();
    return count($rows);
}

function seekPage(PDO $db, string $table, ?string $ts, ?int $id): array {
    $qt = quoteIdentifier($db, $table);
    if ($ts === null || $id === null) {
        $stmt = $db->query("SELECT id,created_at FROM {$qt} ORDER BY created_at DESC, id DESC LIMIT 50");
        $rows = $stmt->fetchAll();
        if (!$rows) return [null,null,0];
        $last = end($rows);
        return [$last['created_at'], (int)$last['id'], count($rows)];
    }
    $sql = "SELECT id,created_at FROM {$qt}
            WHERE (created_at < :ts) OR (created_at = :ts AND id < :id)
            ORDER BY created_at DESC, id DESC
            LIMIT 50";
    $rows = $db->prepare($sql);
    $rows->execute([':ts'=>$ts, ':id'=>$id]);
    $all = $rows->fetchAll();
    $last = $all ? end($all) : null;
    return [$last['created_at'] ?? null, isset($last['id'])?(int)$last['id']:null, count($all)];
}

function csvHeader($fh): void {
    fputcsv($fh, ['ts_iso','pid','mode','iter','ms','rows','ok','code','msg']);
}

function main(): void {
    $a = args();
    $a['table'] = sanitizeIdentifier($a['table']);
    $db = connect($a['dsn'] ?? getenv('DB_DSN'), $a['user'] ?? getenv('DB_USER'), $a['pass'] ?? getenv('DB_PASS'));
    $db->exec(isPg($db) ? "SET TIME ZONE 'UTC'" : "SET time_zone = '+00:00'");
    ensureSchema($db, $a['table']);

    $fh = fopen($a['out'] ?? 'php://stdout', 'w');
    csvHeader($fh);

    $mode = $a['mode'];
    $deadline = microtime(true) + $a['duration'];
    $iter = 0;
    $tsCursor = null; $idCursor = null;

    while (microtime(true) < $deadline) {
        $iter++;
        $t0 = microtime(true);
        $ok = 1; $code = ''; $msg = ''; $rows = 0;
        try {
            switch ($mode) {
                case 'select':
                    $rows = selectRecent($db, $a['table']);
                    break;
                case 'upsert':
                    $email = sprintf('user%06d@example.test', random_int(1, 1000000));
                    $name = 'User '.substr($email, 4, 6);
                    $v = random_int(1, 1000);
                    upsert($db, $a['table'], ['name'=>$name, 'email'=>$email, 'v'=>$v]);
                    $rows = 1;
                    break;
                case 'seek':
                    [$tsCursor,$idCursor,$rows] = seekPage($db, $a['table'], $tsCursor, $idCursor);
                    break;
                default:
                    throw new RuntimeException("Unknown mode: {$mode}");
            }
        } catch (Throwable $e) {
            $ok = 0; $code = method_exists($e,'getCode') ? (string)$e->getCode() : '';
            $msg = substr($e->getMessage(), 0, 120);
        }
        $ms = (int)round((microtime(true)-$t0)*1000);
        fputcsv($fh, [gmdate('c'), getmypid(), $mode, $iter, $ms, $rows, $ok, $code, $msg]);
        if ($a['sleepMs'] > 0) usleep($a['sleepMs']*1000);
    }

    if (is_resource($fh) && $fh !== STDOUT) fclose($fh);
}

main();
