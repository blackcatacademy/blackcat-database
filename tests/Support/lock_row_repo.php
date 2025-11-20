<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use BlackCat\Core\Database;

/**
 * Usage:
 *   php tests/support/lock_row_repo.php "<RepoFqn>" <id> <seconds>
 *
 * Helper process:
 *  - initializes the DB from env (BC_DB, DSN, etc.)
 *  - holds the lock via Repository::lockById($id) for <seconds> seconds
 *  - rolls back the transaction afterward (no data changes)
 */

require __DIR__ . '/../phpunit.bootstrap.php';
require __DIR__ . '/../ci/db_guard.php';

// --- After bootstrap: verify ENV vs actual driver + configure PG timeouts ---
$db  = Database::getInstance();
$pdo = $db->getPdo();
$driver = (string)$pdo->getAttribute(\PDO::ATTR_DRIVER_NAME); // 'mysql' | 'pgsql'
$envRaw = strtolower((string)(getenv('BC_DB') ?: ''));

// normalize aliases to canonical values
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
// === DEBUG helpers (controlled by BC_DEBUG) ===
$isDebug = static function(): bool {
    $val = $_ENV['BC_DEBUG'] ?? getenv('BC_DEBUG') ?? '';
    return $val === '1' || strcasecmp((string)$val, 'true') === 0;
};
$dbg = static function(string $fmt, ...$args) use ($isDebug): void {
    if (!$isDebug()) return;
    error_log('[lock_row_repo] ' . vsprintf($fmt, $args));
};
if (!class_exists($repoFqn)) {
    // attempt autoload (Composer dev autoloader should be available)
    if (!class_exists($repoFqn)) {
        fwrite(STDERR, "Repository class not found: $repoFqn\n");
        exit(3);
    }
}
// Derive the package and Definitions from the repo FQN: ...\Packages\<Pkg>\Repository\...
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
// --- DEBUG: where and how the locker runs ---
$driver = $db->driver();
$server = $db->serverVersion() ?? '?';
$idfp   = $db->id();

// Best-effort diagnostics; must never crash the worker (older MariaDB versions lack some variables)
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
            // MariaDB / older MySQL
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

// Precaution: make MySQL return the full statement on timeout
if ($db->isMysql()) {
    try { $db->exec('SET SESSION innodb_rollback_on_timeout = 1'); }
    catch (\Throwable $_) { /* some MySQL/MariaDB builds treat it as read-only -> safe to ignore */ }
}
$dbg('BEGIN; repo=%s id=%d secs=%d', $repoFqn, $id, $secs);

// Helper to read the version (if available)
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
    $dbg('locked row id=%d; sleeping %d s...', $id, $secs);
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

// Hold the lock for $secs seconds
$left = max(1, $secs);
while ($left > 0) {
    sleep(1);
    $left--;
    if ($isDebug()) {
        $cur = $getVersion();
        if ($cur !== null) $dbg('...holding lock, version=%s, %ds left', (string)$cur, $left);
    }
}
$vend = $getVersion();
if ($vend !== null) $dbg('releasing lock; version before ROLLBACK=%s', (string)$vend);
$dbg('ROLLBACK; lock released');
// Cleanup - keep the state unchanged
if ($pdo->inTransaction()) { $pdo->rollBack(); }
