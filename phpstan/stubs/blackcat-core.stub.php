<?php
// PHPStan stub for BlackCat\Core\Database to expose observability helpers available in local sources.

namespace BlackCat\Core;

class Database
{
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     */
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     */
    public function execWithMeta(string $sql, array $params = [], array $meta = []): int {}
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     */
    public function executeWithMeta(string $sql, array $params = [], array $meta = []): int {}
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     */
    public function fetchWithMeta(string $sql, array $params = [], array $meta = []): mixed {}
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     * @return array<string,mixed>|null
     */
    public function fetchRowWithMeta(string $sql, array $params = [], array $meta = []): ?array {}
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     * @return list<array<string,mixed>>
     */
    public function fetchAllWithMeta(string $sql, array $params = [], array $meta = []): array {}
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     */
    public function fetchOneWithMeta(string $sql, array $params = [], array $meta = []): mixed {}
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     */
    public function fetchValueWithMeta(string $sql, array $params = [], array $meta = []): mixed {}
    /**
     * @param array<string,mixed> $params
     * @param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $params
     * @phpstan-param array<string,mixed> $meta
     */
    public function existsWithMeta(string $sql, array $params = [], array $meta = []): bool {}
    /**
     * @param array<string,mixed> $meta
     * @param array<string,mixed> $opts
     * @phpstan-param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $opts
     */
    public function txWithMeta(callable $fn, array $meta = [], array $opts = []): mixed {}
    /**
     * @param array<string,mixed> $meta
     * @param array<string,mixed> $opts
     * @phpstan-param array<string,mixed> $meta
     * @phpstan-param array<string,mixed> $opts
     */
    public function txRoWithMeta(callable $fn, array $meta = [], array $opts = []): mixed {}
    public function dialect(): string {}
}
