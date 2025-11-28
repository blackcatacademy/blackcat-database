<?php
declare(strict_types=1);

namespace BlackCat\DatabaseCrypto\Adapter;

use BlackCat\Crypto\CryptoManager;
use BlackCat\DatabaseCrypto\Config\EncryptionMap;
use BlackCat\DatabaseCrypto\Gateway\DatabaseGatewayInterface;
use BlackCat\DatabaseCrypto\Mapper\PayloadEncryptor;

final class DatabaseCryptoAdapter
{
    // TODO(crypto-integrations): Introduce a higher-level DatabaseIngressAdapter that
    // wraps blackcat-database repositories so app code can call a single method that
    // validates manifest coverage, encrypts payloads, and forwards to the gateway
    // without touching CryptoManager directly (edge/deployer/etc. will consume it).
    private PayloadEncryptor $encryptor;

    public function __construct(
        private readonly CryptoManager $crypto,
        EncryptionMap $map,
        private readonly DatabaseGatewayInterface $gateway,
    ) {
        $this->encryptor = new PayloadEncryptor($crypto, $map);
    }

    public function insert(string $table, array $payload, array $options = []): mixed
    {
        $transformed = $this->encryptor->transform($table, $payload);
        return $this->gateway->insert($table, $transformed, $options);
    }

    public function update(string $table, array $payload, array $criteria, array $options = []): mixed
    {
        $transformed = $this->encryptor->transform($table, $payload);
        return $this->gateway->update($table, $transformed, $criteria, $options);
    }

    public function encryptPayload(string $table, array $payload): array
    {
        return $this->encryptor->transform($table, $payload);
    }
}
