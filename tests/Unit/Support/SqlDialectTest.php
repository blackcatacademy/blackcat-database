<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\SqlDialect;

final class SqlDialectTest extends TestCase
{
    public function testNormalizeAndFlags(): void
    {
        $this->assertSame('mysql', SqlDialect::normalize('mariadb'));
        $this->assertTrue(SqlDialect::supportsReturning('postgres'));
        $this->assertFalse(SqlDialect::supportsReturning('mysql'));
        $this->assertTrue(SqlDialect::supportsSkipLocked('postgres'));
        $this->assertTrue(SqlDialect::supportsSkipLocked('mysql'));
        $this->assertTrue(SqlDialect::hasILike('postgres'));
        $this->assertFalse(SqlDialect::hasILike('mysql'));
        $this->assertTrue(SqlDialect::hasNativeJson('mysql'));
    }

    public function testPlaceholder(): void
    {
        $this->assertSame('?', SqlDialect::mysql->placeholder(3));
        $this->assertSame('$3', SqlDialect::postgres->placeholder(3));
    }
}
