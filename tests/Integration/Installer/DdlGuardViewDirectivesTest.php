<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class DdlGuardViewDirectivesTest extends TestCase
{
    public function test_mysql_view_has_algorithm_and_security(): void
    {
        $db = Database::getInstance();
        if ($db->isPg()) {
            $this->markTestSkipped('MySQL/MariaDB only');
        }
        $db->exec("DROP VIEW IF EXISTS v_test");
        $db->exec("DROP TABLE IF EXISTS tabx");
        $db->exec("CREATE TABLE tabx (id INT PRIMARY KEY AUTO_INCREMENT, v INT)");
        $db->exec("CREATE ALGORITHM=MERGE SQL SECURITY INVOKER VIEW v_test AS SELECT id,v FROM tabx");

        $row = $db->fetch("SHOW CREATE VIEW v_test");
        $ddl = (string)($row['Create View'] ?? '');
        $this->assertStringContainsString('ALGORITHM=MERGE', $ddl);
        $this->assertStringContainsString('SQL SECURITY INVOKER', $ddl);
    }
}
