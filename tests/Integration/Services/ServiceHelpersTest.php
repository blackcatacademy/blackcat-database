<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\ServiceHelpers;
use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Core\DatabaseException;
use ReflectionClass;

final class ServiceHelpersDummyService
{
    use ServiceHelpers;

    public function __construct(private Database $db, private ?QueryCache $qcache = null) {}
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
            $db->exec('CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)');
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

    public function testTxnTimeoutAndLockWrappers(): void
    {
        $svc = $this->makeSvc();
        $r = $svc->txn(fn($s)=> $s->db()->fetchOne('SELECT COUNT(*) FROM t'));
        $this->assertSame(3, (int)$r);

        $r2 = $svc->withTimeout(5, fn($s)=> $s->db()->fetchOne('SELECT 1'));
        $this->assertSame(1, (int)$r2);

        $r3 = $svc->withLock('demo', 1, fn($s)=> $s->db()->fetchOne('SELECT 1'));
        $this->assertSame(1, (int)$r3);
    }

    public function testRetryHandlesTransientPdo(): void
    {
        $svc = $this->makeSvc();
        $attempts = 0;
        $out = $svc->retry(3, function() use (&$attempts) {
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

        $retry = (new ReflectionClass($svc))->getMethod('retry');
        $retry->setAccessible(true);
        $out = $retry->invoke($svc, 3, $fn);
        $this->assertSame('ok', $out);
        $this->assertSame(2, $calls);
    }

    public function testKeysetWrapperDefaultsPkResultKey(): void
    {
        $svc = $this->makeSvc();
        $sqlBase = 'SELECT id, val FROM t';
        $keyset = (new ReflectionClass($svc))->getMethod('keyset');
        $keyset->setAccessible(true);
        $res = $keyset->invoke(
            $svc, $sqlBase, [], 'id', null, 2, null, 'ASC', false
        );
        $this->assertSame([1,2], array_column($res['items'], 'id'));
        $this->assertSame(2, $res['nextAfter']);
    }
}
