<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\Search;

final class SearchTest extends TestCase
{
    public function testEscapeAndBuild(): void
    {
        $e = Search::escapeLike('a_b%c\\d');
        $this->assertSame('a\\_b\\%c\\\\d', $e);

        $b = Search::build('postgres', 't.name', 'foo', true);
        $this->assertStringContainsString('ILIKE', $b['expr']);
        $this->assertSame('%foo%', $b['param']);

        $any = Search::buildAny('mysql', ['t.a','t.b'], 'bar', true);
        $this->assertStringContainsString('LIKE', $any['expr']);
        $this->assertStringContainsString('ESCAPE', $any['expr']);
        $this->assertSame('%bar%', $any['param']);
    }
}
