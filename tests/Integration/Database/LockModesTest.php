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
        $row = $db->fetch("SELECT * FROM lockme WHERE id=1 FOR UPDATE SKIP LOCKED");
        $db->rollback();

        $this->assertNull($row);
    }

    public function test_nowait_fails_fast_on_pg(): void
    {
        $db = Database::getInstance();
        if (!$db->isPg()) {
            $this->markTestSkipped('NOWAIT is PG-only');
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
