<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use BlackCat\Core\Database;

/**
 * Usage:
 *   php tests/support/lock_row_repo.php "<RepoFqn>" <id> <seconds>
 *
 * Pomocný proces:
 *  - inicializuje DB z env (BC_DB, DSN atd.)
 *  - přes Repository::lockById($id) drží zámek <seconds> sekund
 *  - transakci pak ROLLBACK (nechceme měnit data)
 */

require __DIR__ . '/../phpunit.bootstrap.php';
require __DIR__ . '/../ci/db_guard.php';

// --- Po bootstrapu: zkontroluj shodu ENV vs. skutečný driver + nastav PG timeouty ---
$db  = Database::getInstance();
$pdo = $db->getPdo();
$driver = (string)$pdo->getAttribute(\PDO::ATTR_DRIVER_NAME); // 'mysql' | 'pgsql'
$envRaw = strtolower((string)(getenv('BC_DB') ?: ''));

// normalizace aliasů na kanonické hodnoty
$envNorm = match ($envRaw) {
    'mysql', 'mariadb'                      => 'mysql',
    'pg', 'pgsql', 'postgres', 'postgresql' => 'pgsql',
    default                                 => '',
};

if ($envNorm === '') {
    fwrite(STDERR, "[lock_row_repo] BC_DB not recognized ('{$envRaw}'). Use one of: mysql|mariadb|pg|pgsql|postgres|postgresql.\n");
    exit(7);
}

if ($driver !== $envNorm) {
    fwrite(STDERR, "[lock_row_repo] ENV/driver mismatch: BC_DB(normalized)='{$envNorm}', PDO='{$driver}'. Aborting.\n");
    exit(7);
}
if ($driver === 'pgsql') {
    try {
        $db->exec("SET lock_timeout TO '5s'");
        $db->exec("SET statement_timeout TO '30s'");
        $db->exec("SET idle_in_transaction_session_timeout TO '30s'");
    } catch (\Throwable $e) {
        // non-fatal
    }
}

if ($argc < 4) {
    fwrite(STDERR, "Args: <RepoFqn> <id> <seconds>\n");
    exit(2);
}
$repoFqn = $argv[1];
$id      = (int)$argv[2];
$secs    = (int)$argv[3];
// === DEBUG helpers (řízené BC_DEBUG) ===
$isDebug = static function(): bool {
    $val = $_ENV['BC_DEBUG'] ?? getenv('BC_DEBUG') ?? '';
    return $val === '1' || strcasecmp((string)$val, 'true') === 0;
};
$dbg = static function(string $fmt, ...$args) use ($isDebug): void {
    if (!$isDebug()) return;
    error_log('[lock_row_repo] ' . vsprintf($fmt, $args));
};
if (!class_exists($repoFqn)) {
    // pokus o autoload (Composer dev autoloader by měl být k dispozici)
    if (!class_exists($repoFqn)) {
        fwrite(STDERR, "Repository class not found: $repoFqn\n");
        exit(3);
    }
}
// Odvoď balík a Definitions z repo FQN: …\Packages\<Pkg>\Repository\...
$pkg = null;
if (preg_match('~\\\\Packages\\\\([^\\\\]+)\\\\Repository\\\\~', $repoFqn, $m)) {
    $pkg = $m[1];
}
$defsFqn = $pkg ? "BlackCat\\Database\\Packages\\{$pkg}\\Definitions" : null;
$table = null; $verCol = null; $pkCol = 'id';
if ($defsFqn && class_exists($defsFqn)) {
    $table  = $defsFqn::table();
    $verCol = $defsFqn::versionColumn();
    if (method_exists($defsFqn, 'pk')) {
        $pkCol = (string)$defsFqn::pk() ?: 'id';
    }
}

if (!$pdo->inTransaction()) { $pdo->beginTransaction(); }
$qi = fn($x) => $db->quoteIdent($x);
// --- DEBUG: kde a jak běží locker ---
$driver = $db->driver();
$server = $db->serverVersion() ?? '?';
$idfp   = $db->id();

// Best-effort diagnostika, nikdy nesmí shodit worker (MariaDB starší verze nemají některé proměnné)
$dbName = 'n/a';
try {
    $dbName = $driver === 'mysql'
        ? (string)$db->fetchOne('SELECT DATABASE()')
        : (string)$db->fetchOne('SELECT current_database()');
} catch (\Throwable $__) {}

$iso = 'n/a';
if ($driver === 'mysql') {
    try {
        // MySQL 8+
        $iso = (string)$db->fetchOne('SELECT @@transaction_isolation');
    } catch (\Throwable $__) {
        try {
            // MariaDB / starší MySQL
            $iso = (string)$db->fetchOne('SELECT @@tx_isolation');
        } catch (\Throwable $___) {}
    }
} else {
    try {
        $iso = (string)$db->fetchOne('SHOW transaction_isolation');
    } catch (\Throwable $__) {}
}

$autocommit = 'n/a';
if ($driver === 'mysql') {
    try { $autocommit = (string)$db->fetchOne('SELECT @@autocommit'); } catch (\Throwable $__) {}
}

$lockWait = 'n/a';
if ($driver === 'mysql') {
    try { $lockWait = (string)$db->fetchOne('SELECT @@innodb_lock_wait_timeout'); } catch (\Throwable $__) {}
}

fwrite(STDERR, "[lock_row_repo] driver={$driver} server={$server} db={$dbName} idfp={$idfp} iso={$iso} autocommit={$autocommit} lock_wait={$lockWait}\n");

if ($table && $verCol) {
    $v0 = $db->fetchOne(
        'SELECT '.$qi($verCol).' FROM '.$qi($table).' WHERE '.$qi($pkCol).'=:id',
        [':id'=>$id]
    );
    fwrite(STDERR, "[lock_row_repo] version before FOR UPDATE: {$table}.{$verCol}={$v0} (id={$id})\n");
}

// Pro jistotu: ať MySQL při timeoutu vrátí celý statement
if ($db->isMysql()) {
    try { $db->exec('SET SESSION innodb_rollback_on_timeout = 1'); }
    catch (\Throwable $_) { /* některé MySQL/MariaDB buildy mají read-only → OK ignorovat */ }
}
$dbg('BEGIN; repo=%s id=%d secs=%d', $repoFqn, $id, $secs);

// Helper pro načtení verze (pokud existuje)
$getVersion = static function() use ($db, $table, $verCol, $id, $pkCol, $qi) {
    if (!$table || !$verCol) return null;
    $sql = 'SELECT ' . $qi($verCol) . ' FROM ' . $qi($table) . ' WHERE ' . $qi($pkCol) . ' = :id';
    return $db->fetchOne($sql, [':id' => $id]);
};
$ver0 = $getVersion();
if ($ver0 !== null) $dbg('version before lock=%s', (string)$ver0);

$repo = new $repoFqn($db);
$row  = $repo->lockById($id); // SELECT ... FOR UPDATE
if ($table && $verCol) {
    $v1 = $db->fetchOne(
        'SELECT '.$qi($verCol).' FROM '.$qi($table).' WHERE '.$qi($pkCol).'=:id',
        [':id'=>$id]
    );
    fwrite(STDERR, "[lock_row_repo] version after FOR UPDATE: {$table}.{$verCol}={$v1} (id={$id})\n");
}

if ($row) {
    $dbg('locked row id=%d; sleeping %d s…', $id, $secs);
    $v = $getVersion();
    if ($v !== null) $dbg('version right after lock=%s', (string)$v);
} else {
    $dbg('row id=%d not found — nothing to lock', $id);
}

if (!$row) {
    fwrite(STDERR, "Row not found, id=$id\n");
    if ($table && $verCol) {
        $v2 = $db->fetchOne(
            'SELECT '.$qi($verCol).' FROM '.$qi($table).' WHERE '.$qi($pkCol).'=:id',
            [':id'=>$id]
        );
        fwrite(STDERR, "[lock_row_repo] version before ROLLBACK (still holding lock): {$table}.{$verCol}={$v2} (id={$id})\n");
    }
    if ($pdo->inTransaction()) { 
        $pdo->rollBack(); 
    }
    exit(4);
}

// Drž zámek po dobu $secs
$left = max(1, $secs);
while ($left > 0) {
    sleep(1);
    $left--;
    if ($isDebug()) {
        $cur = $getVersion();
        if ($cur !== null) $dbg('…holding lock, version=%s, %ds left', (string)$cur, $left);
    }
}
$vend = $getVersion();
if ($vend !== null) $dbg('releasing lock; version before ROLLBACK=%s', (string)$vend);
$dbg('ROLLBACK; lock released');
// Uklid — nechceme měnit stav
if ($pdo->inTransaction()) { $pdo->rollBack(); }
