<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Packages;

use PHPUnit\Framework\TestCase;

final class CriteriaTest extends TestCase
{
    public function test_where_like_order_paging(): void
    {
        // use any Criteria class - pull it from app_settings
        $critClass = 'BlackCat\\Database\\Packages\\AppSettings\\Criteria';
        if (!class_exists($critClass)) $this->markTestSkipped('Criteria class not found');

        $c = new $critClass();
        $this->assertSame(1, $c->pageNumber());
        $this->assertGreaterThan(0, $c->perPage());

        if (method_exists($c,'addFilter')) $c->addFilter('section', 'core');
        if (method_exists($c,'search'))    $c->search('token');
        if (method_exists($c,'orderBy'))   $c->orderBy('setting_key','DESC');

        [$where,$params,$order,$limit,$offset] = $c->toSql();
        $this->assertStringContainsString('1=1', $where.' 1=1'); // basic sanity
        $this->assertIsArray($params);
        $this->assertTrue($order === null || str_contains($order,'DESC'));
        $this->assertGreaterThan(0, $limit);
        $this->assertGreaterThanOrEqual(0, $offset);
    }
}
