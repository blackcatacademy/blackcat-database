<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\SqlExpr;
use InvalidArgumentException;
use BlackCat\Core\Database;

final class SqlExprTest extends TestCase
{
    public function testFuncAndAppendMergeParams(): void
    {
        $a = SqlExpr::raw('col = :a', [':a' => 1]);
        $b = SqlExpr::raw('AND col2 = :b', [':b' => 2]);
        $merged = $a->append($b);

        $this->assertSame('col = :a AND col2 = :b', (string)$merged);
        $this->assertSame([':a' => 1, ':b' => 2], $merged->params);
    }

    public function testJoinAndWrapSkipEmptyParts(): void
    {
        $parts = [SqlExpr::raw('a = 1'), '', SqlExpr::raw('b = :b', [':b' => 3])];
        $expr = SqlExpr::join($parts, ' OR ')->wrap('(', ')');
        $this->assertSame('(a = 1 OR b = :b)', (string)$expr);
        $this->assertArrayHasKey(':b', $expr->params);
    }

    public function testIdentListAndJsonSerialize(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn' => 'sqlite::memory:']);
        }
        $db = Database::getInstance();
        $list = SqlExpr::identList($db, ['id','name']);
        $json = $list->jsonSerialize();
        $this->assertArrayHasKey('expr', $json);
        $this->assertSame([], $json['params']);
    }

    public function testMidStatementSemicolonThrows(): void
    {
        $this->expectException(InvalidArgumentException::class);
        new SqlExpr('SELECT *; DROP TABLE t');
    }
}
