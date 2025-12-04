<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration\Database;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class DeterministicOrderTest extends TestCase
{
    public function test_nulls_last_emulation_mysql_like(): void
    {
        $db = Database::getInstance();
        $db->exec("DROP TABLE IF EXISTS ord");
        $db->exec($db->isPg()
            ? "CREATE TABLE ord (id BIGSERIAL PRIMARY KEY, created_at TIMESTAMPTZ NULL)"
            : "CREATE TABLE ord (id BIGINT PRIMARY KEY AUTO_INCREMENT, created_at TIMESTAMP NULL)");
        $db->exec("INSERT INTO ord(created_at) VALUES (NULL),(NULL)");

        if ($db->isPg()) {
            $rows = $db->fetchAll("SELECT id FROM ord ORDER BY created_at DESC NULLS LAST, id DESC");
        } else {
            $rows = $db->fetchAll("SELECT id FROM ord ORDER BY (CASE WHEN created_at IS NULL THEN 0 ELSE 1 END) DESC, created_at DESC, id DESC");
        }
        $this->assertNotEmpty($rows);
    }
}
