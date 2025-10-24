<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

final class ConnFactory
{
    public static function newPdo(): \PDO
    {
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
        $pdo = new \PDO($dsn, $user, $pass, [
            \PDO::ATTR_ERRMODE            => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
            \PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
        if ($which === 'mysql' && defined('PDO::MYSQL_ATTR_USE_BUFFERED_QUERY')) {
            $pdo->setAttribute(\PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false);
            $pdo->exec("SET time_zone = '+00:00'");
        } else {
            $pdo->exec("SET TIME ZONE 'UTC'");
        }
        return $pdo;
    }

    public static function setShortLockTimeout(\PDO $pdo, int $ms = 1000): void
    {
        $which = getenv('BC_DB') ?: 'mysql';
        if ($which === 'mysql') {
            // v sekundách; 1s je rozumné pro test
            $sec = max(1, (int)ceil($ms / 1000));
            $pdo->exec("SET innodb_lock_wait_timeout = {$sec}");
        } else {
            // PG – lock_timeout je v ms
            $pdo->exec("SET LOCAL lock_timeout = '{$ms}ms'");
        }
    }
}
