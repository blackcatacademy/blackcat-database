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
        $this->assertSame('success', $rec['status']);
        $this->assertSame(['result' => 'ok'], $rec['result']);

        $store->fail('key2', 'boom');
        $fail = $store->get('key2');
        $this->assertSame('failed', $fail['status']);
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
