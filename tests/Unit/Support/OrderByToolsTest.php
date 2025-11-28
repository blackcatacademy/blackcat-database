<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\OrderByTools;
use BlackCat\Core\Database;

final class OrderByToolsTest extends TestCase
{
    private static Database $db;

    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn' => 'sqlite::memory:']);
        }
        self::$db = Database::getInstance();
    }

    private function host(): object
    {
        return new class(self::$db) {
            use OrderByTools;
            public function __construct(private Database $db) {}
            public function build(string $order, array $allowed, array $also = [], string $alias = 't', ?string $pk = 'id'): string
            {
                return $this->buildOrderBy($order, $allowed, $this->db, $also, $alias, $pk, true);
            }
        };
    }

    public function testWhitelistsAndTieBreaker(): void
    {
        $host = $this->host();
        $sql = $host->build('ORDER BY name DESC, other ASC', ['id','name']);
        $this->assertStringContainsString('ORDER BY', $sql);
        $quotedPk = self::$db->quoteIdent('t.id');
        $this->assertStringContainsString($quotedPk, $sql); // tie-breaker
        $this->assertStringNotContainsString('other', $sql); // not whitelisted
    }

    public function testAlsoAllowedAlias(): void
    {
        $host = $this->host();
        $sql = $host->build('total DESC', ['id'], ['total']);
        $this->assertStringContainsString('total', $sql);
    }
}
