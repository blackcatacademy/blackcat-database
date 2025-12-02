<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Idempotency\InMemoryIdempotencyStore;

final class InMemoryIdempotencyStoreTest extends TestCase
{
    public function testBeginCommitAndFailLifecycle(): void
    {
        $store = new InMemoryIdempotencyStore();
        $this->assertTrue($store->begin('key1', 1));
        $this->assertFalse($store->begin('key1'));

        $store->commit('key1', ['result' => 'ok']);
        $rec = $store->get('key1');
        $this->assertNotNull($rec);
        $this->assertSame('success', $rec['status']);
        $this->assertArrayHasKey('result', $rec);
        $this->assertSame(['result' => 'ok'], $rec['result']);

        $store->fail('key2', 'boom');
        $fail = $store->get('key2');
        $this->assertNotNull($fail);
        $this->assertSame('failed', $fail['status']);
        $this->assertArrayHasKey('result', $fail);
        $this->assertNull($fail['result']);
    }

    public function testExpiredKeyIsRemoved(): void
    {
        $store = new InMemoryIdempotencyStore();
        $this->assertTrue($store->begin('short', 1));
        sleep(1);
        $this->assertNull($store->get('short'));
    }
}
