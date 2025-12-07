<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Installer;

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

        $call = \Closure::bind(
            function(string $s) { return $this->parseCreateViewHead($s); },
            $guard,
            DdlGuard::class
        );
        [$name, $alg, $sec, $def] = $call($sql);

        $this->assertSame('analytics.v_orders', $name);
        $this->assertSame('MERGE', $alg);
        $this->assertSame('DEFINER', $sec);
        $this->assertSame('`root`@`localhost`', $def);
    }
}
