<?php
declare(strict_types=1);

use BlackCat\Core\Database;

if (!Database::isInitialized()) {
    fwrite(STDERR, "[db-guard] Database not initialized. Check BC_DB and DSNs.\n");
    exit(90);
}

$pdo = Database::getInstance()->getPdo();
$drv = (string)$pdo->getAttribute(PDO::ATTR_DRIVER_NAME); // 'mysql' | 'pgsql'

$raw = strtolower((string)(getenv('BC_DB') ?: ''));
$map = [
    'mysql' => 'mysql', 'mariadb' => 'mysql',
    'pg' => 'pgsql', 'pgsql' => 'pgsql', 'postgres' => 'pgsql', 'postgresql' => 'pgsql',
];
$norm = $map[$raw] ?? '';

if ($norm !== '' && $norm !== $drv) {
    fwrite(STDERR, "[db-guard] ENV/driver mismatch: BC_DB='{$raw}' -> '{$norm}', PDO='{$drv}'.\n");
    exit(91);
}

// For PG configure short session timeouts (safe for parallel runs)
if ($drv === 'pgsql') {
    try {
        $pdo->exec("SET lock_timeout TO '5s'");
        $pdo->exec("SET statement_timeout TO '30s'");
        $pdo->exec("SET idle_in_transaction_session_timeout TO '30s'");
    } catch (\Throwable $e) { /* ignore */ }
}
