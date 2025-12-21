<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Crypto;

use BlackCat\Database\Contracts\DatabaseIngressAdapterInterface;
use BlackCat\Database\Crypto\IngressLocator;
use PHPUnit\Framework\TestCase;

final class IngressLocatorTest extends TestCase
{
    public function testRequireAdapterReturnsExplicitlySetAdapter(): void
    {
        try {
            $adapter = new class implements DatabaseIngressAdapterInterface {
                public function encrypt(string $table, array $payload): array
                {
                    return $payload + ['_table' => $table];
                }
            };

            IngressLocator::setAdapter($adapter);

            $out = IngressLocator::requireAdapter()->encrypt('users', ['id' => 1]);
            self::assertSame(['id' => 1, '_table' => 'users'], $out);
        } finally {
            IngressLocator::setAdapter(null);
        }
    }

    public function testAdapterThrowsWhenNotConfigured(): void
    {
        try {
            // Force "not configured" even if the test bootstrap initializes runtime crypto config.
            IngressLocator::configure(null, '');
            $this->expectException(\RuntimeException::class);
            IngressLocator::adapter();
        } finally {
            IngressLocator::configure(null, null);
        }
    }
}
