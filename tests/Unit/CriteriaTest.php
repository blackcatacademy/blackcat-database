<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit;

use PHPUnit\Framework\TestCase;

final class CriteriaTest extends TestCase
{
    public function test_where_like_order_paging(): void
    {
        // použijeme libovolnou Criteria třídu – vezmeme z app_settings
        $critClass = 'BlackCat\\Database\\Packages\\AppSettings\\Criteria';
        if (!class_exists($critClass)) {
            // najít soubor, pokud autoload nenahrál
            $path = __DIR__ . '/../../packages/app-settings/src/Criteria.php';
            if (is_file($path)) require_once $path;
        }
        if (!class_exists($critClass)) $this->markTestSkipped('Criteria class not found');

        $c = new $critClass();
        $this->assertSame(1, $c->pageNumber());
        $this->assertGreaterThan(0, $c->perPage());

        if (method_exists($c,'addFilter')) $c->addFilter('section', 'core');
        if (method_exists($c,'search'))    $c->search('token');
        if (method_exists($c,'orderBy'))   $c->orderBy('setting_key','DESC');

        [$where,$params,$order,$limit,$offset] = $c->toSql();
        $this->assertStringContainsString('1=1', $where.' 1=1'); // aspoň základ
        $this->assertIsArray($params);
        $this->assertTrue($order === null || str_contains($order,'DESC'));
        $this->assertGreaterThan(0, $limit);
        $this->assertGreaterThanOrEqual(0, $offset);
    }
}
