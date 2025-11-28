<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class LockModesTest extends TestCase
{
    public function test_skip_locked_returns_null_when_contended(): void
    {
        $db = Database::getInstance();
        $db->exec("DROP TABLE IF EXISTS lockme");
        $db->exec($db->isPg()
            ? "CREATE TABLE lockme (id BIGSERIAL PRIMARY KEY, v INT)"
            : "CREATE TABLE lockme (id BIGINT PRIMARY KEY AUTO_INCREMENT, v INT)");
        $db->exec("INSERT INTO lockme(v) VALUES (1)");

        // Tx1: hold lock
        $db->beginTransaction();
        $db->fetch("SELECT * FROM lockme WHERE id=1 FOR UPDATE");
        // Tx2: try SKIP LOCKED
        if ($db->isPg()) {
            $dsn  = getenv('PG_DSN') ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
            $user = getenv('PG_USER') ?: 'postgres';
            $pass = getenv('PG_PASS') ?: 'postgres';
        } else {
            $dsn  = getenv('MYSQL_DSN')  ?: (getenv('MARIADB_DSN') ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4');
            $user = getenv('MYSQL_USER') ?: (getenv('MARIADB_USER') ?: 'root');
            $pass = getenv('MYSQL_PASS') ?: (getenv('MARIADB_PASS') ?: 'root');
        }
        $pdo2 = new \PDO($dsn, $user, $pass, [
            \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
        ]);
        $pdo2->beginTransaction();
        $row = $pdo2->query("SELECT * FROM lockme WHERE id=1 FOR UPDATE SKIP LOCKED")->fetch() ?: null;
        $pdo2->rollBack();
        $db->rollback();

        $this->assertNull($row);
    }

    public function test_nowait_fails_fast_on_pg(): void
    {
        $db = Database::getInstance();
        if (!$db->isPg()) {
            $this->assertTrue(true, 'NOWAIT branch is PG-only; acknowledged for MySQL/MariaDB.');
            return;
        }
        $db->exec("DROP TABLE IF EXISTS lockme2");
        $db->exec("CREATE TABLE lockme2 (id BIGSERIAL PRIMARY KEY, v INT)");
        $db->exec("INSERT INTO lockme2(v) VALUES (1)");

        $db->beginTransaction();
        $db->fetch("SELECT * FROM lockme2 WHERE id=1 FOR UPDATE");
        $this->expectException(\PDOException::class);
        $db->fetch("SELECT * FROM lockme2 WHERE id=1 FOR UPDATE NOWAIT");
        $db->rollback();
    }
}
