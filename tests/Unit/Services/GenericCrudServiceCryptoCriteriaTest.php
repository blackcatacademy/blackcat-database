<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Services;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\ContractRepository;
use BlackCat\Database\Contracts\DatabaseIngressCriteriaAdapterInterface;
use BlackCat\Database\Crypto\IngressLocator;
use BlackCat\Database\Services\GenericCrudService;
use BlackCat\Database\Services\GenericCrudRepositoryShape;
use PHPUnit\Framework\TestCase;

final class GenericCrudServiceCryptoCriteriaTest extends TestCase
{
    public function testExistsByKeysUsesCriteriaAdapterWhenPresent(): void
    {
        if (!class_exists(IngressLocator::class)) {
            self::markTestSkipped('IngressLocator not available.');
        }

        // Avoid any auto boot behavior from env during this unit test.
        IngressLocator::setAdapter(null);

        $db = Database::getInstance();
        $repo = new class implements ContractRepository, GenericCrudRepositoryShape {
            public ?string $lastWhere = null;
            /** @var array<string,mixed>|null */
            public ?array $lastParams = null;

            public function updateByIdWhere(int|string|array $id, array $row, array $where): int { return 0; }
            public function insert(array $row): void {}
            public function insertMany(array $rows): void {}
            public function upsert(array $row): void {}
            public function upsertByKeys(array $row, array $keys, array $updateColumns = []): void {}
            public function updateByKeys(array $keys, array $row): int { return 0; }
            public function updateByIdOptimistic(int|string|array $id, array $row, string|int $versionCol = 'version', int|string|array|null $expectedVersion = null): int { return 0; }
            public function updateByIdExpr(int|string|array $id, array $expr): int { return 0; }
            public function updateById(int|string|array $id, array $row): int { return 0; }
            public function deleteById(int|string|array $id): int { return 0; }
            public function restoreById(int|string|array $id): int { return 0; }
            public function findById(int|string|array $id, array $opts = []): ?array { return null; }
            public function findByIds(array $ids, array $opts = []): array { return []; }
            public function exists(int|string|array $whereSql = 0, array $params = []): bool {
                $this->lastWhere = is_string($whereSql) ? $whereSql : null;
                $this->lastParams = $params;
                return true;
            }
            public function count(string $whereSql = '1=1', array $params = []): int { return 0; }
            /** @param array<string,mixed>|object $criteria */
            public function paginate(mixed $criteria): array { return ['items' => [], 'total' => 0, 'page' => 1, 'perPage' => 10]; }
            public function lockById(int|string|array $id, string $mode = 'wait', string $strength = 'update'): ?array { return null; }
            public function setIngressAdapter(?object $adapter = null, ?string $table = null): void {}
            public function table(): string { return 'users'; }
        };

        $criteriaAdapter = new class implements DatabaseIngressCriteriaAdapterInterface {
            /** @var array<int,array{table:string,criteria:array<string,mixed>}> */
            public array $calls = [];

            public function encrypt(string $table, array $payload): array { return $payload; }

            public function criteria(string $table, array $criteria): array
            {
                $this->calls[] = ['table' => $table, 'criteria' => $criteria];
                if (array_key_exists('email_hash', $criteria)) {
                    $criteria['email_hash'] = 'hmac:' . $criteria['email_hash'];
                }
                return $criteria;
            }
        };

        $svc = (new GenericCrudService($db, $repo, 'id'))->withIngressAdapter($criteriaAdapter, 'users');

        self::assertTrue($svc->existsByKeys(['email_hash' => 'alice@example.com']));
        self::assertSame([['table' => 'users', 'criteria' => ['email_hash' => 'alice@example.com']]], $criteriaAdapter->calls);
        self::assertIsString($repo->lastWhere);
        self::assertIsArray($repo->lastParams);
        self::assertSame('hmac:alice@example.com', $repo->lastParams[':k_email_hash'] ?? null);
    }

    public function testGetByUniqueUsesCriteriaAdapterWhenPresent(): void
    {
        IngressLocator::setAdapter(null);

        $db = Database::getInstance();
        $repo = new class implements ContractRepository, GenericCrudRepositoryShape {
            /** @var array<string,mixed>|null */
            public ?array $lastKeys = null;
            public ?bool $lastAsDto = null;

            public function updateByIdWhere(int|string|array $id, array $row, array $where): int { return 0; }
            public function insert(array $row): void {}
            public function insertMany(array $rows): void {}
            public function upsert(array $row): void {}
            public function upsertByKeys(array $row, array $keys, array $updateColumns = []): void {}
            public function updateByKeys(array $keys, array $row): int { return 0; }
            public function updateByIdOptimistic(int|string|array $id, array $row, string|int $versionCol = 'version', int|string|array|null $expectedVersion = null): int { return 0; }
            public function updateByIdExpr(int|string|array $id, array $expr): int { return 0; }
            public function updateById(int|string|array $id, array $row): int { return 0; }
            public function deleteById(int|string|array $id): int { return 0; }
            public function restoreById(int|string|array $id): int { return 0; }
            public function findById(int|string|array $id, array $opts = []): ?array { return null; }
            public function findByIds(array $ids, array $opts = []): array { return []; }
            public function exists(int|string|array $whereSql = 0, array $params = []): bool { return false; }
            public function count(string $whereSql = '1=1', array $params = []): int { return 0; }
            /** @param array<string,mixed>|object $criteria */
            public function paginate(mixed $criteria): array { return ['items' => [], 'total' => 0, 'page' => 1, 'perPage' => 10]; }
            public function lockById(int|string|array $id, string $mode = 'wait', string $strength = 'update'): ?array { return null; }

            // Optional repository extension used by GenericCrudService::getByUnique()
            public function getByUnique(array $keys, bool $asDto = false): array|object|null
            {
                $this->lastKeys = $keys;
                $this->lastAsDto = $asDto;
                return null;
            }

            public function setIngressAdapter(?object $adapter = null, ?string $table = null): void {}
            public function table(): string { return 'users'; }
        };

        $criteriaAdapter = new class implements DatabaseIngressCriteriaAdapterInterface {
            public function encrypt(string $table, array $payload): array { return $payload; }
            public function criteria(string $table, array $criteria): array
            {
                return ['email_hash' => 'hmac:' . ($criteria['email_hash'] ?? '')];
            }
        };

        $svc = (new GenericCrudService($db, $repo, 'id'))->withIngressAdapter($criteriaAdapter, 'users');
        $svc->getByUnique(['email_hash' => 'alice@example.com'], false);

        self::assertSame(['email_hash' => 'hmac:alice@example.com'], $repo->lastKeys);
        self::assertSame(false, $repo->lastAsDto);
    }
}
