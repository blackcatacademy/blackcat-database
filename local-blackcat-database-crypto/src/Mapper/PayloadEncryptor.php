<?php
declare(strict_types=1);

namespace BlackCat\DatabaseCrypto\Mapper;

use BlackCat\Crypto\CryptoManager;
use BlackCat\DatabaseCrypto\Config\EncryptionMap;
use BlackCat\Crypto\Support\Envelope;

final class PayloadEncryptor
{
    public function __construct(
        private readonly CryptoManager $crypto,
        private readonly EncryptionMap $map
    ) {}

    /**
     * @param array<string,mixed> $payload
     * @return array<string,mixed>
     */
    public function transform(string $table, array $payload): array
    {
        $columns = $this->map->columnsFor($table);
        if ($columns === null) {
            return $payload;
        }

        $result = $payload;
        foreach ($columns as $column => $strategy) {
            if (!array_key_exists($column, $payload)) {
                continue;
            }
            $result[$column] = $this->applyStrategy((array)$strategy, $payload[$column]);
        }
        return $result;
    }

    private function applyStrategy(array $strategy, mixed $value): mixed
    {
        $mode = strtolower((string)($strategy['strategy'] ?? 'encrypt'));
        $context = (string)($strategy['context'] ?? '');
        if ($value === null || $context === '') {
            return $value;
        }

        return match ($mode) {
            'encrypt' => $this->encryptValue($context, $value, $strategy),
            'hmac' => $this->hmacValue($context, $value, $strategy),
            'passthrough' => $value,
            default => throw new \InvalidArgumentException('Unknown strategy ' . $mode),
        };
    }

    private function encryptValue(string $context, mixed $value, array $strategy): string
    {
        $plaintext = is_string($value) ? $value : json_encode($value, JSON_UNESCAPED_SLASHES);
        if ($plaintext === false) {
            throw new \RuntimeException('Unable to serialize payload for encryption');
        }
        $envelope = $this->crypto->encryptContext($context, $plaintext, ['wrapCount' => $strategy['wrap_count'] ?? 0]);
        return $envelope->encode();
    }

    private function hmacValue(string $context, mixed $value, array $strategy): string
    {
        $message = is_scalar($value) ? (string)$value : json_encode($value, JSON_UNESCAPED_SLASHES);
        if ($message === false) {
            throw new \RuntimeException('Unable to serialize payload for HMAC');
        }
        $signature = $this->crypto->hmac($context, $message);
        $encoding = strtolower((string)($strategy['encoding'] ?? 'base64'));
        return match ($encoding) {
            'hex' => bin2hex($signature),
            default => base64_encode($signature),
        };
    }
}
