<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Packages;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Contracts\ContractRepository as RepoContract;

final class RepositoryFacadeSeekFallbackTest extends TestCase
{
    public function testCriteriaFactoryUsesDbInstance(): void
    {
        if (!\BlackCat\Core\Database::isInitialized()) {
            \BlackCat\Core\Database::init(['dsn'=>'sqlite::memory:','user'=>null,'pass'=>null,'options'=>[]]);
        }
        $db = \BlackCat\Core\Database::getInstance();

        $repo = new \BlackCat\Database\Packages\RbacRepoSnapshots\Repository($db);
        $crit = $repo->criteria();

        $this->assertInstanceOf(\BlackCat\Database\Packages\RbacRepoSnapshots\Criteria::class, $crit);
        // ensure dialect set via driver
        $sqlPieces = $crit->orderBy('id', 'DESC')->toSql(true);
        $this->assertIsArray($sqlPieces);
    }

    public function testPaginateBySeekFallbackResetsPaging(): void
    {
        if (!\BlackCat\Core\Database::isInitialized()) {
            \BlackCat\Core\Database::init(['dsn'=>'sqlite::memory:','user'=>null,'pass'=>null,'options'=>[]]);
        }
        $db = \BlackCat\Core\Database::getInstance();

        // Anonymous stub implementing the generated interface (not KeysetRepoContract),
        // so the facade will take the fallback branch.
        $inner = new class implements \BlackCat\Database\Packages\RbacRepoSnapshots\Repository\RbacRepoSnapshotRepositoryInterface {
            public function insert(array $row): void {}
            public function insertMany(array $rows): void {}
            public function upsert(array $row): void {}
            public function upsertRevive(array $row): void {}
            public function upsertByKeys(array $row, array $keys, array $updateColumns = []): void {}
            public function upsertByKeysRevive(array $row, array $keys, array $updateColumns = []): void {}
            public function upsertMany(array $rows): int { return 0; }
            public function upsertManyRevive(array $rows): int { return 0; }
            public function updateByIdWhere(int|string|array $id, array $row, array $where): int { return 0; }
            public function updateById(int|string|array $id, array $row): int { return 0; }
            public function deleteById(int|string|array $id): int { return 0; }
            public function restoreById(int|string|array $id): int { return 0; }
            public function findById(int|string|array $id): ?array { return null; }
            public function findAllByIds(array $ids): array { return []; }
            public function getById(int|string|array $id, bool $asDto = false): array|\BlackCat\Database\Packages\RbacRepoSnapshots\Dto\RbacRepoSnapshotDto|null { return null; }
            public function getByUnique(array $keyValues, bool $asDto = false): array|\BlackCat\Database\Packages\RbacRepoSnapshots\Dto\RbacRepoSnapshotDto|null { return null; }
            public function exists(string $whereSql = '1=1', array $params = []): bool { return false; }
            public function count(string $whereSql = '1=1', array $params = []): int { return 0; }
            public function existsById(int|string|array $id): bool { return false; }
            public function paginate(object $criteria): array {
                return ['items' => [['id' => 1]], 'total' => 1, 'page' => 1, 'perPage' => 5];
            }
            public function paginateBySeek(object $criteria, array $order, ?array $cursor, int $limit): array
            {
                return [[['id' => 1]], null];
            }
            public function lockById(int|string|array $id, string $mode = 'wait', string $strength = 'update'): ?array { return null; }
        };

        // Build facade but swap the inner repo via helper (keeps constructor untouched)
        $facade = new \BlackCat\Database\Packages\RbacRepoSnapshots\Repository($db);
        $facade->_setRepositoryForTests($inner);

        $c = (new \BlackCat\Database\Packages\RbacRepoSnapshots\Criteria())->orderBy('id', 'DESC');
        [$items, $cursor] = $facade->paginateBySeek($c, ['col' => 'id', 'dir' => 'desc', 'pk' => 'id'], null, 5);

        $this->assertSame([['id' => 1]], $items);
        $this->assertNull($cursor);
    }
}
