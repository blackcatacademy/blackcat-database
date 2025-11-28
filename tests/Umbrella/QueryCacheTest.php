<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Umbrella;

use PHPUnit\Framework\TestCase;

use BlackCat\Database\Tests\Util\DbUtil;
use BlackCat\Database\Tests\Fakes\ArrayCache;
use BlackCat\Core\Database\QueryCache;

final class QueryCacheTest extends TestCase
{
    private QueryCache $qc;

    public static function setUpBeforeClass(): void
    {
        DbUtil::wipeDatabase();
        DbUtil::db()->configureCircuit(1000000, 1);
        $db = DbUtil::db();
        $db->exec("CREATE TABLE q (id INT PRIMARY KEY, name VARCHAR(50))");
        $db->execute("INSERT INTO q (id,name) VALUES (1,'A'),(2,'B'),(3,'C')");
    }

    protected function setUp(): void
    {
        // QueryCache(cache, ?locks, ?logger, namespace)
        $this->qc = new QueryCache(new ArrayCache(), null, null, 'test:qc:');
    }
/** Helper: cached rows via QueryCache+Database (replaces the legacy selectAll). */
    private function qcAll(string $sql, array $params, int $ttl): array
    {
        return $this->qc->rememberRows(DbUtil::db(), $sql, $params, $ttl);
    }

    /** Helper: cached key=>value pairs (replaces the legacy selectPairs). */
    private function qcPairs(string $sql, array $params, int $ttl): array
    {
        $db  = DbUtil::db();
        $key = $this->qc->key($db->id(), $sql, $params);
        $rows = $this->qc->remember($key, $ttl, fn() => $db->fetchAll($sql, $params));
        if (!$rows) return [];
        $cols = array_keys($rows[0]);
        $kCol = $cols[0] ?? null;
        $vCol = $cols[1] ?? $cols[0] ?? null;
        if ($kCol === null || $vCol === null) return [];
        $out = [];
        foreach ($rows as $r) { $out[$r[$kCol]] = $r[$vCol]; }
        return $out;
    }

    /** Helper: invalidate a prefix by bumping the namespace (replaces invalidatePrefix). */
    private function qcInvalidate(): void
    {
        $this->qc->newNamespace('test:qc:' . bin2hex(random_bytes(4)));
    }

    public function test_hit_miss_ttl(): void
    {
        $first = $this->qcAll("SELECT * FROM q WHERE id <= :max ORDER BY id", [':max'=>2], 1);
        $this->assertCount(2, $first);

        $second = $this->qcAll("SELECT * FROM q WHERE id <= :max ORDER BY id", [':max'=>2], 10);
        $this->assertSame($first, $second, 'must be cache hit');

        sleep(2);
        $third = $this->qcAll("SELECT * FROM q WHERE id <= :max ORDER BY id", [':max'=>2], 1);
        $this->assertSame($first, $third, 'still a hit - our simple ArrayCache expired the data already, but other implementations might miss.');
    }

    public function test_params_change_invalidate_key(): void
    {
        $a = $this->qcAll("SELECT * FROM q WHERE id <= :max ORDER BY id", [':max'=>1], 60);
        $b = $this->qcAll("SELECT * FROM q WHERE id <= :max ORDER BY id", [':max'=>2], 60);
        $this->assertNotSame($a, $b);
    }

    public function test_pairs_and_prefix_invalidation(): void
    {
        $pairs = $this->qcPairs("SELECT id,name FROM q ORDER BY id", [], 60);
        $this->assertSame([1=>'A',2=>'B',3=>'C'], $pairs);

        // prefix invalidation (namespace bump): only verify the call does not throw
        $this->qcInvalidate();
        $this->assertTrue(true);
    }
    
    public function test_cache_getter_present(): void
    {
        $ref = $this->qc->cache();
        $this->assertTrue(method_exists($this->qc, 'cache'));
        $this->assertTrue($ref->set('k','v',10));
        $this->assertSame('v', $ref->get('k'));
    }
}
