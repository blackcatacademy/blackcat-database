<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Core;

use BlackCat\Core\Cache\MemoryCache;
use BlackCat\Core\Cache\InvalidKeyException;
use PHPUnit\Framework\TestCase;

final class MemoryCacheTest extends TestCase
{
    public function testBasicSetGetHasDelete(): void
    {
        $c = new MemoryCache();
        $this->assertFalse($c->has('k'));
        $this->assertNull($c->get('k'));

        $this->assertTrue($c->set('k', 123, 10));
        $this->assertTrue($c->has('k'));
        $this->assertSame(123, $c->get('k'));
        $this->assertTrue($c->delete('k'));
        $this->assertFalse($c->has('k'));
        $this->assertNull($c->get('k'));
    }

    public function testTtlSecondsAndExpiration(): void
    {
        $c = new MemoryCache();
        $this->assertTrue($c->set('x', 'v', 5));
        $this->assertSame('v', $c->get('x'));

        // move time forward by 6 seconds
        $c->setNowSkew(6);
        $this->assertNull($c->get('x')); // expirace => default null
        $this->assertFalse($c->has('x'));
    }

    public function testTtlDateInterval(): void
    {
        $c = new MemoryCache();
        $this->assertTrue($c->set('i', 'ok', new \DateInterval('PT2S')));
        $this->assertSame('ok', $c->get('i'));
        $c->setNowSkew(3);
        $this->assertNull($c->get('i'));
    }

    public function testNoStoreTtlZeroOrNegative(): void
    {
        $c = new MemoryCache();
        $this->assertTrue($c->set('n', 'will-not-store', 0));  // no-store
        $this->assertNull($c->get('n'));
        $this->assertTrue($c->set('m', 'nope', -5));           // no-store
        $this->assertNull($c->get('m'));
    }

    public function testGetMultipleSetMultipleDeleteMultiple(): void
    {
        $c = new MemoryCache();
        $this->assertTrue($c->setMultiple(['a' => 1, 'b' => 2, 'c' => 3], 10));

        $r = $c->getMultiple(['a', 'b', 'x'], 'D');
        $this->assertSame(['a' => 1, 'b' => 2, 'x' => 'D'], $r);

        $this->assertTrue($c->deleteMultiple(['a', 'c']));
        $this->assertFalse($c->has('a'));
        $this->assertTrue($c->has('b'));
        $this->assertFalse($c->has('c'));
    }

    public function testLruEvictionRespectsLastAccess(): void
    {
        $c = new MemoryCache(2); // max 2 items
        $c->set('k1', 'v1', 100);
        $c->set('k2', 'v2', 100);

        // use k1 -> it becomes the freshest entry
        $this->assertSame('v1', $c->get('k1'));

        // add k3 -> the oldest (k2) should be evicted
        $c->set('k3', 'v3', 100);

        $this->assertTrue($c->has('k1')); // kept alive by the last access
        $this->assertFalse($c->has('k2')); // LRU out
        $this->assertTrue($c->has('k3'));

        $this->assertSame(2, $c->debugCount());
    }

    public function testPruneExpiredBeforeLru(): void
    {
        $c = new MemoryCache(2);
        $c->set('a', 'va', 1);
        $c->set('b', 'vb', 100);
        $c->set('c', 'vc', 100);

        // a expirovala
        $c->setNowSkew(2);

        // next set should prune 'a', then evict one LRU entry to stay within capacity
        $c->set('d', 'vd', 100);

        $this->assertFalse($c->has('a')); // expired and removed
        $this->assertFalse($c->has('b')); // LRU evicted after prune
        $this->assertTrue($c->has('c'));
        $this->assertTrue($c->has('d')); // cache keeps latest two entries
        $this->assertSame(2, $c->debugCount());
    }

    public function testInvalidKeys(): void
    {
        $c = new MemoryCache();
        $this->expectException(InvalidKeyException::class);
        $c->get('');
    }

    public function testReservedCharacterKeys(): void
    {
        $c = new MemoryCache();
        $bad = ['a:b', 'x/y', 'u@v', 'p(q)', 'r){', 'foo\\bar', 'x{y}'];

        foreach ($bad as $k) {
            try {
                $c->set($k, 1);
                $this->fail("Key '$k' should be rejected.");
            } catch (InvalidKeyException $e) {
                $this->assertTrue(true);
            }
        }
    }

    public function testAliasSetNowSkewForTests(): void
    {
        $c = new MemoryCache();
        $c->set('t', 'ok', 2);
        $c->setNowSkew(5);
        $this->assertNull($c->get('t'));
    }
}
