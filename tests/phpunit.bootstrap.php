<?php
declare(strict_types=1);

use BlackCat\Core\Database;

require __DIR__ . '/../vendor/autoload.php';

// Stejná inicializace jako v tests/ci/run.php (paměť šetrnější)
$which = getenv('BC_DB') ?: 'mysql';
if ($which === 'mysql') {
    $dsn  = getenv('MYSQL_DSN')  ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';
    $user = getenv('MYSQL_USER') ?: 'root';
    $pass = getenv('MYSQL_PASS') ?: 'root';
} else {
    $dsn  = getenv('PG_DSN')  ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
    $user = getenv('PG_USER') ?: 'postgres';
    $pass = getenv('PG_PASS') ?: 'postgres';
}

Database::init([
    'dsn' => $dsn,
    'user'=> $user,
    'pass'=> $pass,
    'init_commands' => ["SET TIME ZONE 'UTC'"]
]);

$pdo = Database::getInstance()->getPdo();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
$pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
if ($which === 'mysql' && defined('PDO::MYSQL_ATTR_USE_BUFFERED_QUERY')) {
    $pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false);
}

// Helpery k dispozici všem testům
require __DIR__ . '/support/DbHarness.php';
require __DIR__ . '/support/RowFactory.php';
require __DIR__ . '/support/AssertSql.php';
