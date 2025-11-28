<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Tenancy\TenantScope;
use BlackCat\Database\Tests\Support\DummyCriteria;

final class TenantScopeTest extends TestCase
{

    public function testApplyAndSqlAndAttach(): void
    {
        $scope = new TenantScope([10,20]);
        $c = new DummyCriteria();
        $scope->apply($c, 'tenant_id'); // typed against BaseCriteria
        $sqlParts = (array)$c->toSql(true);
        $this->assertIsArray($sqlParts);
        $flat = implode(' ', array_map(static fn($v) => is_string($v) ? $v : '', $sqlParts));
        $this->assertStringContainsString('tenant_id', $flat);

        $sql = $scope->sql('mysql','t.tenant_id');
        $this->assertStringContainsString('IN', $sql['expr']);
        $this->assertCount(2, $sql['params']);

        // attach / guard
        $single = new TenantScope(10);
        $row = $single->attach(['name'=>'x'], 'tenant_id');
        $this->assertArrayHasKey('tenant_id', $row);
        $this->expectException(\LogicException::class);
        (new TenantScope([1,2]))->attach(['name'=>'y'], 'tenant_id'); // ambiguous
    }

    public function testGuardRowMismatch(): void
    {
        $this->expectException(\LogicException::class);
        (new TenantScope(5))->guardRow(['tenant_id'=>6], 'tenant_id');
    }
}
