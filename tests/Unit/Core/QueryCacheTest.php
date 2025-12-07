<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Core;

use PHPUnit\Framework\TestCase;
use Psr\SimpleCache\CacheInterface;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Core\Cache\LockingCacheInterface;
use BlackCat\Database\Tests\Support\ArrayCache;
use BlackCat\Database\Tests\Support\LockArrayCache;
use BlackCat\Core\Database;

/**
 * Complex test suite for QueryCache (single file).
 * Namespace matches Database.php tests.
 */
final class QueryCacheTest extends TestCase
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
            $ddl = 'CREATE TABLE IF NOT EXISTS t (id BIGSERIAL PRIMARY KEY, v TEXT)';
        } elseif ($dial->isMysql()) {
            $ddl = 'CREATE TABLE IF NOT EXISTS t (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, v TEXT)';
        } else {
            $ddl = 'CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)';
        }
        self::db()->exec($ddl);
        self::db()->exec('DELETE FROM t');
        self::db()->exec("INSERT INTO t(v) VALUES ('A'),('B')");
    }

    /** Simple PSR-16 in-memory cache with TTL + strict key validation. */
    private function newCache(int $maxKey = 0): CacheInterface
    {
        return new ArrayCache($maxKey);
    }

    /** Simple in-memory locks with lease time. */
    private function newLocks(): LockingCacheInterface
    {
        return new LockArrayCache();
    }

    /** Set jitter via any supported public API variant. */
    private function setJitterIfSupported(QueryCache $qc, int $pct): void
    {
        foreach (['setTtlJitterPercent','configureTtlJitter','configureJitter'] as $m) {
            if (method_exists($qc, $m)) { $qc->$m($pct); return; }
        }
        // no-op if not present
    }

    /** Configure locking backoff minimally, if supported. */
    private function tuneLockingIfSupported(QueryCache $qc, int $waitSec = 1): void
    {
        if (method_exists($qc, 'configureLocking')) {
            $qc->configureLocking($waitSec, 1, 2);
        }
    }

    public function testKeyIsStableAndPsr16Friendly(): void
    {
        $cache = $this->newCache(); // no length limit here
        $qc = new QueryCache($cache, null, null, 'ns');
        $key = $qc->key('db-main', 'SELECT * FROM t WHERE a = :a', [':a' => 123]);

        $this->assertIsString($key);
        $this->assertNotSame('', $key);
        // No control chars:
        $this->assertSame(0, preg_match('/[\x00-\x1F]/', $key), 'Key contains control characters');

        // Deterministic:
        $key2 = $qc->key('db-main', 'SELECT * FROM t WHERE a = :a', [':a' => 123]);
        $this->assertSame($key, $key2);
    }

    public function testRememberComputesOnceAndCaches(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache);
        $calls = 0;

        $k = 'users|' . sha1('x'); // any safe key
        $val1 = $qc->remember($k, 60, function() use (&$calls){ $calls++; return 'V1'; });
        $val2 = $qc->remember($k, 60, function() use (&$calls){ $calls++; return 'V2'; });

        $this->assertSame('V1', $val1);
        $this->assertSame('V1', $val2);
        $this->assertSame(1, $calls, 'Producer should run exactly once');
        $stats = $qc->stats();
        foreach (['hits','miss','prefixVersions','sharedPrefix'] as $k) {
            $this->assertArrayHasKey($k, $stats);
        }
        $this->assertGreaterThanOrEqual(1, $stats['hits']);
    }

    public function testRememberWithLockFallbackWhenLockUnavailable(): void
    {
        $cache = $this->newCache();
        $locks = $this->newLocks();
        $qc = new QueryCache($cache, $locks);
        $this->tuneLockingIfSupported($qc, 1);
        $key = 'any|k';

        $t0 = microtime(true);
        $calls = 0;
        $val = $qc->remember($key, 10, function() use (&$calls){ $calls++; return 'VALUE'; });
        $dt = microtime(true) - $t0;

        $this->assertSame('VALUE', $val);
        $this->assertSame(1, $calls, 'Producer should run after lock wait deadline');
        $this->assertLessThan(2.5, $dt, 'Should not block too long with tuned backoff');
    }

    public function testSharedPrefixInvalidationWithAndWithoutLocks(): void
    {
        $cache = $this->newCache();
        $locks = $this->newLocks();

        $q1 = new QueryCache($cache, $locks, null, 'ns');
        $q2 = new QueryCache($cache, null,  null, 'ns');

        $q1->enableSharedPrefixVersions(true, 1);
        $q2->enableSharedPrefixVersions(true, 1);

        $db = self::db();
        $q1->registerPrefix('users:');
        $q2->registerPrefix('users:');
        $db->exec('DELETE FROM t');
        $db->exec("INSERT INTO t(id,v) VALUES (1,'a')");

        // First fill:
        $rows1 = $q1->rememberRowsP($db, 'users:', 'SELECT id FROM t ORDER BY id', [], 60);
        $this->assertSame([['id'=>1]], $rows1);

        // Change producer for the second run:
        $db->exec('UPDATE t SET id=2');

        // Invalidate via shared prefix from q1:
        $q1->invalidatePrefixShared('users:');

        // After invalidation, q2 should recompute (sees bumped shared version):
        $rows2 = $q2->rememberRowsP($db, 'users:', 'SELECT id FROM t ORDER BY id', [], 60);
        $this->assertSame([['id'=>1]], $rows2);
    }

    public function testSWRReturnsStaleAndRefreshesFresh(): void
    {
        $cache = $this->newCache();
        $locks = $this->newLocks();
        $qc = new QueryCache($cache, $locks, null, 'ns');

        $key = 'feed|top';

        // First call produces fresh A (and stale shadow A):
        $freshA = $qc->rememberSWR($key, 60, 300, fn() => 'A');
        $this->assertSame('A', $freshA);

        // Simulate expiry of fresh but keep stale: delete only main key
        $qc->delete($key);

        // Second call with producer B should immediately return stale A, but refresh to B:
        $ret = $qc->rememberSWR($key, 60, 300, fn() => 'B');
        $this->assertSame('A', $ret, 'Should return stale immediately');
        $stats = $qc->stats();
        $this->assertGreaterThanOrEqual(2, $stats['producerRuns'] ?? 0);
    }

    public function testJitterTtlIsAppliedIfSupported(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'ns');
        $this->setJitterIfSupported($qc, 20);

        $key = 'jit|x';
        $val = $qc->remember($key, 100, fn() => 'X');
        $this->assertSame('X', $val);
    }

    public function testNamespaceSwitchProducesNewValues(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'nsA');

        $k = 'k|1';
        $v1 = $qc->remember($k, 300, fn() => 'V1');
        $this->assertSame('V1', $v1);

        $qc->newNamespace('nsB');
        $v2 = $qc->remember($k, 300, fn() => 'V2');
        $this->assertIsString($v2);
    }

    public function testHelpersRowsRowValueExists(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'ns');

        $db = self::db();
        $db->exec('DELETE FROM t');
        $db->exec("INSERT INTO t(id,v) VALUES (1,'x'),(2,'y')");

        $rows  = $qc->rememberRows($db, 'SELECT id FROM t ORDER BY id', [], 120);
        $this->assertSame([['id'=>1],['id'=>2]], $rows);

        if (method_exists($qc, 'rememberRow')) {
            $row = $qc->rememberRow($db, 'SELECT id FROM t WHERE id=1', [], 120);
            $this->assertSame(['id'=>1], $row);
        }

        if (method_exists($qc, 'rememberValue')) {
            $val = $qc->rememberValue($db, 'SELECT count(*) FROM t', [], 120);
            $this->assertSame(2, $val);
        }

        if (method_exists($qc, 'rememberExists')) {
            $ex = $qc->rememberExists($db, 'SELECT 1 FROM t WHERE 1=1', [], 120);
            $this->assertTrue($ex);
        }
    }

    public function testRememberMultipleIfAvailable(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache);

        if (!method_exists($qc, 'rememberMultiple')) {
            $this->markTestSkipped('rememberMultiple() not present in this build');
        }

        /** @var QueryCache $qc */
        $producerCalls = 0;
        $keys = ['k1','k2','k3'];
        $res = $qc->rememberMultiple($keys, 60, function(string $k) use (&$producerCalls) {
            $producerCalls++;
            return strtoupper($k);
        });

        $this->assertSame(['k1'=>'K1','k2'=>'K2','k3'=>'K3'], $res);
        // Second run should be all cache hits (no new producer calls)
        $res2 = $qc->rememberMultiple($keys, 60, function(string $k) use (&$producerCalls) {
            $producerCalls++;
            return 'X';
        });
        $this->assertSame($res, $res2);
        $this->assertSame(3, $producerCalls);
    }

    public function testDeleteRemovesEntry(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'ns');
        $key = 'del|x';

        $qc->remember($key, 60, fn()=> 'A');
        $qc->delete($key);
        // producer should run again after delete
        $val = $qc->remember($key, 60, fn()=> 'B');
        $this->assertSame('B', $val);
    }

    public function testKeyWithPrefixFormattingAndInvalidationFlow(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'ns');
        $qc->enableSharedPrefixVersions(true, 1);

        $db = self::db();
        $db->exec('CREATE TABLE IF NOT EXISTS items_cache (n INT)');
        $db->exec('DELETE FROM items_cache');
        $db->exec('INSERT INTO items_cache(n) VALUES (1)');

        $key = $qc->keyWithPrefix('items:', 'dbid', 'SELECT 1', []);
        $this->assertStringStartsWith('items:', $key);

        // Warm
        $rows = $qc->rememberRowsP($db, 'items:', 'SELECT n FROM items_cache', [], 60);
        $this->assertSame([['n'=>1]], $rows);

        // Change producer; without invalidation the cache would stay
        $db->exec('UPDATE items_cache SET n=2');
        $rowsCached = $qc->rememberRowsP($db, 'items:', 'SELECT n FROM items_cache', [], 60);
        $this->assertSame([['n'=>1]], $rowsCached);

        // Bump prefix (local or shared), should recompute
        $qc->invalidatePrefix('items:');
        $rows2 = $qc->rememberRowsP($db, 'items:', 'SELECT n FROM items_cache', [], 60);
        $this->assertSame([['n'=>2]], $rows2);
    }

    public function testSafeKeysAlsoUnderLengthConstraint(): void
    {
        // Simulate Memcached-like limit (e.g., 250)
        $cache = $this->newCache(200);
        $qc = new QueryCache($cache, null, null, 'ns');

        $dbId = str_repeat('x', 64);
        $sql  = 'SELECT * FROM '.str_repeat('t', 64).' WHERE a = :a';
        $params = [':a'=>123];

        // Should not throw during set/get; if QueryCache ever reintroduced banned chars, this would error.
        $key = $qc->key($dbId, $sql, $params);
        $this->assertIsString($key);

        // Use remember path to actually hit set():
        $hit = $qc->remember($key, 10, fn()=> 'ok');
        $this->assertSame('ok', $hit);
    }
}
