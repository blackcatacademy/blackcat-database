<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Packages;

use DateTimeImmutable;
use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\Attributes\DataProvider;

/**
 * Generic smoke tests for generated Criteria helpers across packages.
 */
final class CriteriaHelpersGenericTest extends TestCase
{
    /**
     * @return array<int,array{class:string,path:string}>
     */
    public static function criteriaClasses(): array
    {
        $cases = [];
        foreach (glob(__DIR__ . '/../../../packages/*/src/Criteria.php') ?: [] as $path) {
            $ns = null;
            foreach (file($path) ?: [] as $line) {
                if (preg_match('/^namespace\s+([^;]+);/', $line, $m)) {
                    $ns = trim($m[1]);
                    break;
                }
            }
            if ($ns === null) {
                continue;
            }
            $class = $ns . '\\Criteria';
            $cases[] = ['class' => $class, 'path' => $path];
        }
        return $cases;
    }

    #[DataProvider('criteriaClasses')]
    public function testHelpers(string $class, string $path): void
    {
        if (!class_exists($class)) {
            $this->markTestSkipped("$class not available");
        }

        $c = new $class();

        if (method_exists($c, 'byId')) {
            [$where, $params] = $c->byId(123)->toSql(true);
            $this->assertIsString($where);
            $this->assertIsArray($params);
        } else {
            $this->assertTrue(true, 'byId helper not generated.');
        }

        if (method_exists($c, 'byIds')) {
            [$whereIn, $paramsIn] = $c->byIds([1, 2, 3])->toSql(true);
            $this->assertIsString($whereIn);
            $this->assertGreaterThanOrEqual(0, \count($paramsIn));

            [$whereEmpty] = $c->byIds([])->toSql(true);
            $this->assertIsString($whereEmpty);
        } else {
            $this->assertTrue(true, 'byIds helper not generated.');
        }

        $from = new DateTimeImmutable('-1 day');
        $to   = new DateTimeImmutable('now');
        $ts   = new DateTimeImmutable('now');

        if (method_exists($c, 'createdBetween')) {
            [$whereBetween, $paramsBetween] = $c->createdBetween($from, $to)->toSql(true);
            $this->assertStringContainsString('BETWEEN', $whereBetween);
            $this->assertGreaterThanOrEqual(2, \count($paramsBetween));
        } else {
            $this->assertTrue(true, 'createdBetween() not generated (no created_at).');
        }

        if (method_exists($c, 'updatedSince')) {
            [$whereSince, $paramsSince] = $c->updatedSince($ts)->toSql(true);
            $this->assertStringContainsString('>=', $whereSince);
            $this->assertNotEmpty($paramsSince);
        } else {
            $this->assertTrue(true, 'updatedSince() not generated (no updated_at).');
        }
    }
}
