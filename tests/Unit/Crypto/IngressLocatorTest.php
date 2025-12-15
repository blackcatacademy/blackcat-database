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
        $prev = getenv('BLACKCAT_DB_ENCRYPTION_REQUIRED');
        putenv('BLACKCAT_DB_ENCRYPTION_REQUIRED'); // ensure not required

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
            if ($prev === false) {
                putenv('BLACKCAT_DB_ENCRYPTION_REQUIRED');
            } else {
                putenv('BLACKCAT_DB_ENCRYPTION_REQUIRED=' . $prev);
            }
            IngressLocator::setAdapter(null);
        }
    }

    public function testAdapterThrowsWhenRequiredAndNotConfigured(): void
    {
        $prev = getenv('BLACKCAT_DB_ENCRYPTION_REQUIRED');
        putenv('BLACKCAT_DB_ENCRYPTION_REQUIRED=1');

        try {
            IngressLocator::configure(null, null);
            $this->expectException(\RuntimeException::class);
            IngressLocator::adapter();
        } finally {
            if ($prev === false) {
                putenv('BLACKCAT_DB_ENCRYPTION_REQUIRED');
            } else {
                putenv('BLACKCAT_DB_ENCRYPTION_REQUIRED=' . $prev);
            }
            IngressLocator::configure(null, null);
        }
    }
}

