<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\OperationResult;
use RuntimeException;

final class OperationResultTest extends TestCase
{
    public function testOkFailAndMapTap(): void
    {
        $ok = OperationResult::ok(['a'=>1], 'c1')->withMeta(['x'=>1])->withCode('ok')->withHttp(200);
        $this->assertTrue($ok->isOk());
        $m  = $ok->map(fn($d)=>$d['a']+1)->tap(fn($r)=>$this->assertSame(200,$r->httpStatus));
        $this->assertSame(2, $m->data);

        $fail = OperationResult::fail('nope', 'c2', ['y'=>2], 'not_found', 404);
        $this->assertTrue($fail->isFail());
        $this->expectException(RuntimeException::class);
        $fail->requireOk();
    }
}
