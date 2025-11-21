<?php

declare(strict_types=1);

namespace BlackCat\Database\Services;

/**
 * Runtime-declared shape for repositories consumed by GenericCrudService.
 *
 * Implementations typically come from generated repositories in ./packages.
 * Methods are intentionally permissive; not every repository supports all of them.
 */
interface GenericCrudRepositoryShape
{
    /** @param array<string,mixed> $row */
    public function insert(array $row): void;

    /** @param list<array<string,mixed>> $rows */
    public function insertMany(array $rows): void;

    /** @param array<string,mixed> $row */
    public function updateById(int|string|array $id, array $row): int;

    public function deleteById(int|string|array $id): int;

    /** @param array<string,mixed> $opts @return array<string,mixed>|null */
    public function findById(int|string|array $id, array $opts = []): ?array;

    /**
     * @param list<int|string|array> $ids
     * @param array<string,mixed> $opts
     * @return list<array<string,mixed>>
     */
    public function findByIds(array $ids, array $opts = []): array;

    /** @param array<string,mixed> $criteria @return array<string,mixed> */
    public function paginate(array $criteria): array;

    public function exists(int|string|array $id): bool;

    /** @param array<string,mixed> $row */
    public function upsert(array $row): void;

    /**
     * @param array<string,mixed> $row
     * @param list<string>|array<string,mixed> $keys
     */
    public function upsertByKeys(array $row, array $keys): void;

    /**
     * @param list<string>|array<string,mixed> $keys
     * @param array<string,mixed> $row
     */
    public function updateByKeys(array $keys, array $row): int;

    /** @return array<string,mixed>|null */
    public function lockById(int|string|array $id): ?array;

    /**
     * @param array<string,mixed> $row
     * @param array<string,mixed>|null $expectedVersion
     */
    public function updateByIdOptimistic(int|string|array $id, array $row, string $versionCol, int|string|array|null $expectedVersion = null): int;

    /** @param array<string,mixed> $expr */
    public function updateByIdExpr(int|string|array $id, array $expr): int;

    /** Optional helper to propagate ingress adapter */
    public function setIngressAdapter(?object $adapter = null, ?string $table = null): void;

    /** Optional table name helper */
    public function table(): string;
}
