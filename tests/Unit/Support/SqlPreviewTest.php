<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\SqlPreview;

final class SqlPreviewTest extends TestCase
{
    public function testPreviewCollapsesWhitespaceAndLimits(): void
    {
        $sql = "SELECT *\nFROM t\nWHERE a = 1";
        $preview = SqlPreview::preview($sql, 10);
        $this->assertSame('SELECT *…', $preview);
    }

    public function testFirstLineSkipsComments(): void
    {
        $sql = "-- comment\n/* block */\nSELECT 1";
        $first = SqlPreview::firstLine($sql);
        $this->assertSame('SELECT 1', $first);
    }
}
