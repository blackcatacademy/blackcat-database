<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\JsonFilters;

final class JsonFiltersTest extends TestCase
{
    public function testContainsMysqlAndPg(): void
    {
        $r1 = JsonFilters::contains('mysql', 'data', ['a'=>1]);
        $this->assertStringContainsString('JSON_CONTAINS', $r1['expr']);
        $this->assertIsString($r1['param']);

        $r2 = JsonFilters::contains('postgres', 'data', ['a'=>1]);
        $this->assertStringContainsString('@>', $r2['expr']);
        $this->assertIsString($r2['param']);
    }

    public function testGetTextMysqlAndPg(): void
    {
        $m = JsonFilters::getText('mysql', 'data', 'a.b.c');
        $this->assertStringContainsString('JSON_EXTRACT', $m['expr']);
        $this->assertSame('$.a.b.c', $m['param']);

        $p = JsonFilters::getText('postgres', 'data', 'a.b.c');
        $this->assertStringContainsString('#>>', $p['expr']);
        $this->assertSame('{a,b,c}', $p['param']);
    }
}
