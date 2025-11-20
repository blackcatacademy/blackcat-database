<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Support\DdlGuard;

final class DdlGuardTest extends TestCase
{
    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn' => 'sqlite::memory:']);
        }
    }

    public function testParseCreateViewHead(): void
    {
        $db = Database::getInstance();
        $guard = new DdlGuard($db, SqlDialect::mysql);

        $sql = <<<SQL
CREATE ALGORITHM=MERGE DEFINER=`root`@`localhost` SQL SECURITY DEFINER
VIEW `analytics`.`v_orders` AS
SELECT 1 AS x
SQL;

        $rm = new ReflectionMethod($guard, 'parseCreateViewHead');
        $rm->setAccessible(true);
        [$name, $alg, $sec, $def] = $rm->invoke($guard, $sql);

        $this->assertSame('analytics.v_orders', $name);
        $this->assertSame('MERGE', $alg);
        $this->assertSame('DEFINER', $sec);
        $this->assertSame('`root`@`localhost`', $def);
    }
}
