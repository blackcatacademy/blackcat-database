<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\ServiceHelpers;
use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Core\DatabaseException;

final class ServiceHelpersDummyService
{
    use ServiceHelpers;

    public function __construct(private Database $db, private ?QueryCache $qcache = null) {}

    // Expose protected helpers for tests
    public function db(): Database { return $this->db; }
}

final class ServiceHelpersTest extends TestCase
{
    private static bool $dbReady = false;

    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn'=>'sqlite::memory:','user'=>null,'pass'=>null,'options'=>[]]);
        }
        if (!self::$dbReady) {
            $db = Database::getInstance();
            if ($db->dialect()->isMysql()) {
                $db->exec('CREATE TABLE IF NOT EXISTS t (id BIGINT AUTO_INCREMENT PRIMARY KEY, v TEXT)');
            } elseif ($db->dialect()->isPg()) {
                $db->exec('CREATE TABLE IF NOT EXISTS t (id BIGSERIAL PRIMARY KEY, v TEXT)');
            } else {
                $db->exec('CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)');
            }
            $db->exec('DELETE FROM t');
            for ($i=0;$i<3;$i++) {
                $db->execute('INSERT INTO t(v) VALUES (?)', ['x'.$i]);
            }
            self::$dbReady = true;
        }
    }

    private function makeSvc(): object
    {
        return new ServiceHelpersDummyService(Database::getInstance());
    }

    private function callMethod(object $obj, string $method, mixed ...$args): mixed
    {
        $closure = \Closure::bind(
            function(...$inner) use ($method) { return $this->{$method}(...$inner); },
            $obj,
            get_class($obj)
        );
        return $closure(...$args);
    }

    public function testTxnTimeoutAndLockWrappers(): void
    {
        $svc = $this->makeSvc();
        $db  = Database::getInstance();
        $r = $this->callMethod($svc, 'txn', fn() => $db->fetchOne('SELECT COUNT(*) FROM t'));
        $this->assertSame(3, (int)$r);

        $r2 = $this->callMethod($svc, 'withTimeout', 5, fn() => $db->fetchOne('SELECT 1'));
        $this->assertSame(1, (int)$r2);

        $r3 = $this->callMethod($svc, 'withLock', 'demo', 1, fn() => $db->fetchOne('SELECT 1'));
        $this->assertSame(1, (int)$r3);
    }

    public function testRetryHandlesTransientPdo(): void
    {
        $svc = $this->makeSvc();
        $attempts = 0;
        $out = $this->callMethod($svc, 'retry', 3, function() use (&$attempts) {
            $attempts++;
            if ($attempts === 1) {
                $e = new PDOException('serialization');
                $e->errorInfo = ['40001', null, 'serialization failure'];
                throw $e;
            }
            return 'ok';
        });
        $this->assertSame('ok', $out);
        $this->assertGreaterThan(1, $attempts);
    }

    public function testRetryHandlesDatabaseExceptionWrappingPdo(): void
    {
        $svc = $this->makeSvc();
        $calls = 0;

        $fn = function() use (&$calls) {
            $calls++;
            if ($calls === 1) {
                $pdoe = new PDOException('deadlock');
                $pdoe->errorInfo = ['40001', 0, 'serialization failure'];
                throw new DatabaseException('wrap', 0, $pdoe);
            }
            return 'ok';
        };

        $out = $this->callMethod($svc, 'retry', 3, $fn);
        $this->assertSame('ok', $out);
        $this->assertSame(2, $calls);
    }

    public function testKeysetWrapperDefaultsPkResultKey(): void
    {
        $svc = $this->makeSvc();
        $sqlBase = 'SELECT id, v FROM t';
        $res = $this->callMethod($svc, 'keyset', $sqlBase, [], 'id', null, 2, null, 'ASC', false);
        $ids = array_column($res['items'], 'id');
        $this->assertCount(2, $ids);
        $this->assertSame($ids[1], $res['nextAfter']);
    }
}
