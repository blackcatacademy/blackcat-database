<?php
declare(strict_types=1);

namespace BlackCat\DatabaseCrypto\Gateway;

/**
 * Lightweight stub to satisfy Database crypto gateway resolution during static analysis.
 * External packages may provide a richer implementation; this keeps typehints intact.
 */
interface DatabaseGatewayInterface
{
    /**
     * @param array<string,mixed> $payload
     * @param array<string,mixed> $options
     */
    public function insert(string $table, array $payload, array $options = []): mixed;

    /**
     * @param array<string,mixed> $payload
     * @param array<string,mixed> $criteria
     * @param array<string,mixed> $options
     */
    public function update(string $table, array $payload, array $criteria, array $options = []): mixed;
}
