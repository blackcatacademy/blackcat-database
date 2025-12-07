<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\SqlSplitter;
use BlackCat\Database\SqlDialect;

final class SqlSplitterTest extends TestCase
{
    public function testSplitsStatementsWithComments(): void
    {
        $sql = "-- comment\nCREATE TABLE t(id INT); INSERT INTO t VALUES (1);";
        $parts = SqlSplitter::split($sql, SqlDialect::mysql);
        $this->assertCount(2, $parts);
        $this->assertStringContainsString('CREATE TABLE', $parts[0]);
    }

    public function testHandlesCustomDelimiter(): void
    {
        $sql = <<<SQL
        DELIMITER $$
        CREATE FUNCTION demo() RETURNS void AS $$
        BEGIN
            PERFORM 1;
        END$$
        DELIMITER ;
        SELECT 1;
        SQL;
        $parts = SqlSplitter::split($sql, SqlDialect::mysql);
        $this->assertGreaterThanOrEqual(1, count($parts));
        $this->assertStringContainsString('CREATE FUNCTION', $parts[0]);
        $this->assertStringContainsString('SELECT 1', implode(';', $parts));
    }

    public function testHandlesPgDollarQuotedStrings(): void
    {
        $sql = <<<'SQL'
DO $$BEGIN RAISE NOTICE 'hi'; END$$; SELECT '\xAA';
SQL;
        $parts = SqlSplitter::split($sql, SqlDialect::postgres);
        $this->assertCount(2, $parts);
        $this->assertStringContainsString('SELECT', $parts[1]);
    }
}
