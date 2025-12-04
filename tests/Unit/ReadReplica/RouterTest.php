<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\ReadReplica;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\ReadReplica\Router;
use BlackCat\Core\Database;

final class RouterTest extends TestCase
{
    private static ?Database $db = null;

    private static function db(): Database
    {
        if (self::$db === null) {
            throw new \RuntimeException('Database not initialized');
        }
        return self::$db;
    }

    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn'=>'sqlite::memory:','user'=>null,'pass'=>null,'options'=>[]]);
        }
        self::$db = Database::getInstance();
        $dial = self::db()->dialect();
        if ($dial->isPg()) {
            $ddl = 'CREATE TABLE IF NOT EXISTS demo (id BIGSERIAL PRIMARY KEY, v INT)';
        } elseif ($dial->isMysql()) {
            $ddl = 'CREATE TABLE IF NOT EXISTS demo (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, v INT)';
        } else {
            $ddl = 'CREATE TABLE IF NOT EXISTS demo (id INTEGER PRIMARY KEY AUTOINCREMENT, v INT)';
        }
        self::db()->exec($ddl);
        self::db()->exec('DELETE FROM demo');
        self::db()->exec('INSERT INTO demo(v) VALUES (1)');
    }

    public function testReadQueriesHitReplicaWhenAvailable(): void
    {
        $primary = self::db();
        $replica = self::db();

        $router = new Router($primary, $replica);
        $picked = $router->pick('SELECT * FROM demo', ['corr' => 'c1']);
        $this->assertSame($replica, $picked);
    }

    public function testStickyAfterWriteKeepsReadsOnPrimary(): void
    {
        $primary = self::db();
        $replica = self::db();

        $router = new Router($primary, $replica, 5000);
        $router->execWithMeta('INSERT INTO demo(v) VALUES (2)', [], ['corr' => 'sticky']);
        $picked = $router->pick('SELECT COUNT(*) FROM demo', ['corr' => 'sticky']);
        $this->assertSame($primary, $picked);
    }
}
