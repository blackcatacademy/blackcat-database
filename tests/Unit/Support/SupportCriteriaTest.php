<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Tenancy\TenantScope;
use BlackCat\Database\Tests\Support\DummyCriteria;

final class SupportCriteriaTest extends TestCase
{

    public function testFiltersOpsBetweenNullsAndOrder(): void
    {
        $c = (new DummyCriteria())
            ->addFilter('status','ok')
            ->where('created_at','>=','2025-01-01')
            ->between('id',1,10)
            ->isNotNull('name')
            ->orderBySafe('created_at','DESC', true);

        [$where,$p,$order,$limit,$offset] = $c->toSql(true);
        $this->assertStringContainsString('t.status =', $where);
        $this->assertStringContainsString('t.created_at >=', $where);
        $this->assertStringContainsString('t.id BETWEEN', $where);
        $this->assertStringContainsString('t.name IS NOT NULL', $where);
        $this->assertNotNull($order);
        $this->assertSame(10, $limit);
        $this->assertSame(0, $offset);
        $this->assertNotEmpty($p);
    }

    public function testSearchLikeDialectSwitch(): void
    {
        $c = (new DummyCriteria())->setDialect('postgres')->useCaseInsensitiveLike(true)->search('foo');
        [$where] = $c->toSql(true);
        $this->assertStringContainsString('ILIKE', $where);

        $c = (new DummyCriteria())->setDialect('mysql')->useCaseInsensitiveLike(true)->search('foo');
        [$where2] = $c->toSql(true);
        $this->assertStringContainsString('LIKE', $where2);
        $this->assertStringNotContainsString('ILIKE', $where2);
    }

    public function testTenantScopeApply(): void
    {
        $c = new DummyCriteria();
        $scope = new TenantScope([1,2,3]);
        $c->applyTenantScope($scope, 'tenant_id');
        [$where] = $c->toSql(true);
        $this->assertStringContainsString('t.tenant_id IN', $where);
    }

    public function testSeekOverridesOffset(): void
    {
        $c = (new DummyCriteria())->seek('id', 100, 'ASC', true)->setPerPage(5)->setPage(3);
        [$where,$p,$order,$limit,$offset] = $c->toSql(true);
        $this->assertStringContainsString('t.id >=', $where);
        $this->assertSame(5, $limit);
        $this->assertSame(0, $offset); // seek vynuluje offset
        $this->assertNotNull($order);
    }

    public function testJoinAndRawAndExplicitLimitOffset(): void
    {
        $c = (new DummyCriteria())
            ->join('LEFT JOIN x j ON j.id = t.id', [':j'=>1])
            ->whereRaw('(t.id + :k) > 0', [':k'=>0]);
        $c->limit(7)->offset(4);

        [, $params,, $limit, $offset, $joins] = $c->toSql(true);
        $this->assertSame(7, $limit);
        $this->assertSame(4, $offset);
        $this->assertStringContainsString('LEFT JOIN x', $joins);
        $this->assertArrayHasKey(':j', $params);
        $this->assertArrayHasKey(':k', $params);
    }
}
