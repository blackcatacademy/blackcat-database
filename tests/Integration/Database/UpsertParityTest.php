<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration\Database;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class UpsertParityTest extends TestCase
{
    public function test_upsert_insert_and_update_paths(): void
    {
        $db = Database::getInstance();
        if ($db->isPg()) {
            try { $db->exec('ROLLBACK'); } catch (\Throwable) {}
        }
        $db->exec("DROP TABLE IF EXISTS upar");
        $sql = $db->isPg()
            ? "CREATE TABLE upar (email TEXT PRIMARY KEY, name TEXT, updated_at TIMESTAMPTZ NULL)"
            : "CREATE TABLE upar (email VARCHAR(120) PRIMARY KEY, name VARCHAR(50), updated_at TIMESTAMP NULL)";
        $db->exec($sql);

        // Insert path
        $now = $db->isPg() ? "NOW()" : "CURRENT_TIMESTAMP";
        $db->exec("INSERT INTO upar(email,name,updated_at) VALUES (:e,:n, $now)", [':e'=>'a@x', ':n'=>'A']);

        // Update path via upsert semantics
        if ($db->isPg()) {
            $db->exec("INSERT INTO upar(email,name,updated_at) VALUES (:e,:n,$now)
                       ON CONFLICT (email) DO UPDATE SET name=EXCLUDED.name, updated_at=$now",
                       [':e'=>'a@x', ':n'=>'AA']);
        } else {
            $db->exec("INSERT INTO upar(email,name,updated_at) VALUES (:e,:n,$now)
                       ON DUPLICATE KEY UPDATE name=VALUES(name), updated_at=$now",
                       [':e'=>'a@x', ':n'=>'AA']);
        }

        $name = (string)$db->fetchOne("SELECT name FROM upar WHERE email='a@x'");
        $this->assertSame('AA', $name);
    }
}
