<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Core;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Tests\Support\ArrayCache;

final class QueryCacheMetricsTest extends TestCase
{
    public function test_hits_and_misses_and_prefix_invalidation(): void
    {
        // Assuming ArrayCache is available in tests; otherwise mock PSR-16
        $file = sys_get_temp_dir() . '/qc_' . bin2hex(random_bytes(4));
        $cache = new ArrayCache();
        $qc = new QueryCache($cache);

        $val1 = $qc->remember('users:list', 10, fn() => 123);
        $val2 = $qc->remember('users:list', 10, fn() => 456);

        $this->assertSame(123, $val1);
        $this->assertSame(123, $val2);

        $qc->invalidatePrefix('users:');
        $val3 = $qc->remember('users:list', 10, fn() => 789);
        $this->assertSame(789, $val3);
    }
}
