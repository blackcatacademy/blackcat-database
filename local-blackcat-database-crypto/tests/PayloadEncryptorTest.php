<?php
declare(strict_types=1);

namespace BlackCat\DatabaseCrypto\Tests;

use BlackCat\Crypto\Config\CryptoConfig;
use BlackCat\Crypto\CryptoManager;
use BlackCat\DatabaseCrypto\Config\EncryptionMap;
use BlackCat\DatabaseCrypto\Mapper\PayloadEncryptor;
use PHPUnit\Framework\TestCase;

final class PayloadEncryptorTest extends TestCase
{
    private CryptoManager $crypto;

    protected function setUp(): void
    {
        parent::setUp();
        $config = CryptoConfig::fromEnv([
            'BLACKCAT_KEYS_DIR' => __DIR__ . '/../fixtures/keys',
        ]);
        $this->crypto = CryptoManager::boot($config);
    }

    public function testEncryptsConfiguredColumns(): void
    {
        $map = EncryptionMap::fromArray([
            'tables' => [
                'users' => [
                    'columns' => [
                        'ssn' => ['strategy' => 'encrypt', 'context' => 'core.vault'],
                        'email_hash' => ['strategy' => 'hmac', 'context' => 'core.hmac.email', 'encoding' => 'hex'],
                    ],
                ],
            ],
        ]);
        $encryptor = new PayloadEncryptor($this->crypto, $map);

        $payload = [
            'id' => 1,
            'ssn' => '123-45-6789',
            'email_hash' => 'alice@example.com',
        ];
        $transformed = $encryptor->transform('users', $payload);

        self::assertNotSame($payload['ssn'], $transformed['ssn']);
        self::assertStringStartsWith('ey', $transformed['ssn']); // envelope base64
        self::assertNotSame($payload['email_hash'], $transformed['email_hash']);
        self::assertMatchesRegularExpression('/^[0-9a-f]+$/', $transformed['email_hash']);
    }
}
