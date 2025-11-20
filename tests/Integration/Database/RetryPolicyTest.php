<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class RetryPolicyTest extends TestCase
{
    public function test_unique_violation_is_not_retried(): void
    {
        $db = Database::getInstance();
        $db->exec("DROP TABLE IF EXISTS uniqx");
        $db->exec($db->isPg()
            ? "CREATE TABLE uniqx (id BIGSERIAL PRIMARY KEY, email TEXT UNIQUE)"
            : "CREATE TABLE uniqx (id BIGINT PRIMARY KEY AUTO_INCREMENT, email VARCHAR(120) UNIQUE)");
        $db->exec("INSERT INTO uniqx(email) VALUES ('a@x')");

        $this->expectException(\PDOException::class);
        $db->exec("INSERT INTO uniqx(email) VALUES ('a@x')");
    }
}
