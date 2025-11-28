<?php
declare(strict_types=1);

namespace BlackCat\DatabaseCrypto\Gateway;

interface DatabaseGatewayInterface
{
    public function insert(string $table, array $payload, array $options = []): mixed;
    public function update(string $table, array $payload, array $criteria, array $options = []): mixed;
}
