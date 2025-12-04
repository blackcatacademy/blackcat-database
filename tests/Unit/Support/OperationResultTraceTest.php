<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Support\OperationResult;

final class OperationResultTraceTest extends TestCase
{
    public function test_correlation_id_and_meta_are_carried(): void
    {
        $r = OperationResult::ok(['x'=>1], 'corr-123', ['retries'=>2]);
        $this->assertTrue($r->ok);
        $this->assertSame('corr-123', $r->correlationId);
        $this->assertSame(2, $r->meta['retries'] ?? null);
    }
}
