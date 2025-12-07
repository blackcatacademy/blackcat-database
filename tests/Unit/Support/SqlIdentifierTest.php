<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\SqlIdentifier;
use InvalidArgumentException;
use BlackCat\Core\Database;

final class SqlIdentifierTest extends TestCase
{
    private static Database $db;

    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn' => 'sqlite::memory:']);
        }
        self::$db = Database::getInstance();
    }

    public function testQiQualifiesMultiPartIdentifiers(): void
    {
        $this->assertSame(self::$db->quoteIdent('t.id'), SqlIdentifier::qi(self::$db, 't.id'));
        $this->assertSame(self::$db->quoteIdent('t') . '.*', SqlIdentifier::tableStar(self::$db, 't'));
    }

    public function testQualifySkipsExpressions(): void
    {
        $expr = SqlIdentifier::qualifyOrExpr(self::$db, 'COUNT(*)', 't');
        $this->assertSame('COUNT(*)', $expr);
    }

    public function testQLIstAndAs(): void
    {
        $list = SqlIdentifier::qList(self::$db, ['id','name']);
        $this->assertStringContainsString(self::$db->quoteIdent('id'), $list);
        $as = SqlIdentifier::qAs(self::$db, 'name', 'alias');
        $this->assertStringContainsString('AS', $as);
    }

    public function testInvalidIdentifierThrows(): void
    {
        $this->expectException(InvalidArgumentException::class);
        SqlIdentifier::qi(self::$db, 'foo; DROP');
    }
}
