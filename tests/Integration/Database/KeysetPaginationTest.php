<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration\Database;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class KeysetPaginationTest extends TestCase
{
    public function test_seek_pagination_is_stable_across_insert_between_pages(): void
    {
        $db = Database::getInstance();
        $db->exec("DROP TABLE IF EXISTS kp");
        $db->exec($db->isPg()
            ? "CREATE TABLE kp (id BIGSERIAL PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), name TEXT)"
            : "CREATE TABLE kp (id BIGINT PRIMARY KEY AUTO_INCREMENT, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, name VARCHAR(50))");

        for ($i=1;$i<=120;$i++) {
            $db->exec("INSERT INTO kp(name) VALUES (:n)", [':n'=>"n{$i}"]);
        }

        $page1 = $db->fetchAll("SELECT id,created_at FROM kp ORDER BY created_at DESC, id DESC LIMIT 25");
        $last = end($page1);
        $cursorTs = $last['created_at']; $cursorId = $last['id'];

        $db->exec($db->isPg()
            ? "INSERT INTO kp(created_at,name) VALUES (NOW() - INTERVAL '10 seconds', 'mid')"
            : "INSERT INTO kp(created_at,name) VALUES (NOW() - INTERVAL 10 SECOND, 'mid')");

        $sql = "SELECT id,created_at FROM kp
                WHERE (created_at < :ts_before) OR (created_at = :ts_eq AND id < :id)
                ORDER BY created_at DESC, id DESC LIMIT 25";
        $page2 = $db->fetchAll($sql, [
            ':ts_before' => $cursorTs,
            ':ts_eq'     => $cursorTs,
            ':id'        => $cursorId,
        ]);

        $ids1 = array_column($page1,'id'); $ids2 = array_column($page2,'id');
        $this->assertSame([], array_values(array_intersect($ids1,$ids2)));
        $this->assertCount(25, $page2);
    }
}
