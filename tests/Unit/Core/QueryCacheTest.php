<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Core;

use PHPUnit\Framework\TestCase;
use Psr\SimpleCache\CacheInterface;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Core\Database as CoreDatabase;
use BlackCat\Core\Cache\LockingCacheInterface;
use BlackCat\Database\Tests\Support\ArrayCache;
use BlackCat\Database\Tests\Support\LockArrayCache;

/**
 * Complex test suite for QueryCache (single file).
 * Namespace matches Database.php tests.
 */
final class QueryCacheTest extends TestCase
{
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

    /** Create a PHPUnit mock of Core Database with basic methods. */
    private function mockDb(string $id, array $behaviors): CoreDatabase
    {
        $db = $this->getMockBuilder(CoreDatabase::class)
            ->disableOriginalConstructor()
            ->onlyMethods(['id','fetchAll','fetch','fetchValue','exists'])
            ->getMock();

        $db->method('id')->willReturn($id);
        foreach ($behaviors as $method => $return) {
            $db->method($method)->willReturnCallback(is_callable($return) ? $return : fn() => $return);
        }
        return $db;
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
        $this->assertSame(['hits','miss','prefixVersions','sharedPrefix'], array_keys($stats));
        $this->assertGreaterThanOrEqual(1, $stats['hits']);
    }

    public function testRememberWithLockFallbackWhenLockUnavailable(): void
    {
        $cache = $this->newCache();
        $locks = $this->newLocks();
        $qc = new QueryCache($cache, $locks);
        $this->tuneLockingIfSupported($qc, 1);

        // Hold the exact lock name QueryCache will use.
        $key = 'any|k';
        // The internal lock name is 'q:' . $appliedNamespaceKey. We can't know nsHash,
        // but because our Locking impl is permissive, we simulate contention by first
        // call attempting to acquire and failing (we'll hijack acquire to always fail by pre-holding *any* name).
        // To be realistic, we pre-hold lock that will be used: we need appliedNamespace(key) == key when no prefixes.
        /** @var LockArrayCache $locks */
        $locks->forceHold('q:' . $key, 2);

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

        $db = $this->mockDb('db1', [
            'fetchAll' => fn() => [['id'=>1]],
        ]);

        // First fill:
        $rows1 = $q1->rememberRowsP($db, 'users:', 'SELECT 1', [], 60);
        $this->assertSame([['id'=>1]], $rows1);

        // Change producer for the second run:
        $db2 = $this->mockDb('db1', [
            'fetchAll' => fn() => [['id'=>2]],
        ]);

        // Without invalidation, should still hit cache:
        $rowsCached = $q2->rememberRowsP($db2, 'users:', 'SELECT 1', [], 60);
        $this->assertSame([['id'=>1]], $rowsCached);

        // Invalidate via shared prefix from q1:
        $q1->invalidatePrefixShared('users:');

        // After invalidation, q2 should recompute (sees bumped shared version):
        $rows2 = $q2->rememberRowsP($db2, 'users:', 'SELECT 1', [], 60);
        $this->assertSame([['id'=>2]], $rows2);
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
        $cache->delete('ns|feed|top'); // matches QueryCache format ns|...|...

        // Second call with producer B should immediately return stale A, but refresh to B:
        $ret = $qc->rememberSWR($key, 60, 300, fn() => 'B');
        $this->assertSame('A', $ret, 'Should return stale immediately');

        // Now reading normal path should be B:
        $this->assertSame('B', $cache->get('ns|feed|top'));
    }

    public function testJitterTtlIsAppliedIfSupported(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'ns');
        $this->setJitterIfSupported($qc, 20);

        $key = 'jit|x';
        $qc->remember($key, 100, fn() => 'X');

        // We cannot observe exact TTL, but we can overwrite and ensure the call does not throw
        // and the key exists immediately; basic smoke (functional correctness).
        $this->assertSame('X', $cache->get('ns|jit|x'));
    }

    public function testNamespaceSwitchProducesNewValues(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'nsA');

        $k = 'k|1';
        $qc->remember($k, 300, fn() => 'V1');
        $this->assertSame('V1', $cache->get('nsA|k|1'));

        $qc->newNamespace('nsB');
        $qc->remember($k, 300, fn() => 'V2');

        $this->assertSame('V2', $cache->get('nsB|k|1'));
        // Old value still present under previous namespace:
        $this->assertSame('V1', $cache->get('nsA|k|1'));
    }

    public function testHelpersRowsRowValueExists(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'ns');

        $db = $this->mockDb('dbX', [
            'fetchAll'  => fn() => [['id'=>1], ['id'=>2]],
            'fetch'     => fn() => ['id'=>7],
            'fetchValue'=> fn() => 42,
            'exists'    => fn() => true,
        ]);

        $rows  = $qc->rememberRows($db, 'SELECT * FROM t', [], 120);
        $this->assertSame([['id'=>1],['id'=>2]], $rows);

        if (method_exists($qc, 'rememberRow')) {
            $row = $qc->rememberRow($db, 'SELECT * FROM t LIMIT 1', [], 120);
            $this->assertSame(['id'=>7], $row);
        }

        if (method_exists($qc, 'rememberValue')) {
            $val = $qc->rememberValue($db, 'SELECT count(*) FROM t', [], 120);
            $this->assertSame(42, $val);
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
        $this->assertSame('A', $cache->get('ns|del|x'));

        $qc->delete($key);
        $this->assertNull($cache->get('ns|del|x'));
    }

    public function testKeyWithPrefixFormattingAndInvalidationFlow(): void
    {
        $cache = $this->newCache();
        $qc = new QueryCache($cache, null, null, 'ns');
        $qc->enableSharedPrefixVersions(true, 1);

        $db = $this->mockDb('dbid', [
            'fetchAll' => fn() => [['n'=>1]],
        ]);

        $key = $qc->keyWithPrefix('items:', 'dbid', 'SELECT 1', []);
        $this->assertStringStartsWith('items:', $key);

        // Warm
        $rows = $qc->rememberRowsP($db, 'items:', 'SELECT 1', [], 60);
        $this->assertSame([['n'=>1]], $rows);

        // Change producer; without invalidation the cache would stay
        $db2 = $this->mockDb('dbid', ['fetchAll' => fn() => [['n'=>2]]]);
        $rowsCached = $qc->rememberRowsP($db2, 'items:', 'SELECT 1', [], 60);
        $this->assertSame([['n'=>1]], $rowsCached);

        // Bump prefix (local or shared), should recompute
        $qc->invalidatePrefix('items:');
        $rows2 = $qc->rememberRowsP($db2, 'items:', 'SELECT 1', [], 60);
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
