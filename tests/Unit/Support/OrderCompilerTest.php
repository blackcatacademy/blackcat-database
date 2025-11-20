<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\OrderCompiler;

final class OrderCompilerTest extends TestCase
{
    public function testCompileRespectsNullsPerDialect(): void
    {
        $dsl = 'created_at DESC NULLS LAST, id ASC';
        $pg = OrderCompiler::compile($dsl, 'postgres');
        $this->assertStringContainsString('NULLS LAST', $pg);

        $my = OrderCompiler::compile($dsl, 'mysql');
        $this->assertStringContainsString('CASE WHEN (created_at) IS NULL THEN 1', $my);
    }

    public function testTieBreakerAddedWhenStable(): void
    {
        $items = [['expr'=>'name','dir'=>'DESC','nulls'=>'AUTO']];
        $sql = OrderCompiler::compile($items, 'postgres', alias: 't', tiePk: 'id', stable: true);
        $this->assertStringContainsString('ORDER BY', $sql);
        $this->assertStringContainsString('"t"."id"', $sql);
    }

    public function testParseItemsStripsOrderBy(): void
    {
        $items = OrderCompiler::parseItems('ORDER BY name DESC, created_at');
        $this->assertCount(2, $items);
        $this->assertSame('DESC', $items[0]['dir']);
    }
}
