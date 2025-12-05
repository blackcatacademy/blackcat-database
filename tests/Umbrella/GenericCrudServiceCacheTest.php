<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Umbrella;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Services\GenericCrudService;
use BlackCat\Database\Support\ServiceHelpers;
use BlackCat\Database\Tests\Fakes\ArrayCache;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Util\DbUtil;
use BlackCat\Database\Services\GenericCrudRepositoryShape;

final class GenericCrudServiceCacheTest extends TestCase
{
    private function makeRepo(): \BlackCat\Database\Contracts\ContractRepository&GenericCrudRepositoryShape {
        return new class implements \BlackCat\Database\Contracts\ContractRepository, GenericCrudRepositoryShape {
            public int $hits = 0;
            public function insert(array $_): void {}
            public function insertMany(array $rows): void {}
            public function upsert(array $_): void {}
            public function upsertMany(array $rows): void {}
            public function updateById(array|string|int $_, array $__): int { return 1; }
            public function updateByIdWhere(array|string|int $_, array $__row, array $__where): int { return 1; }
            public function updateByIdOptimistic(array|string|int $_, array $__row, string $__versionCol, array|string|int|null $__expectedVersion = null): int { return 1; }
            public function updateByIdExpr(array|string|int $_, array $__expr): int { return 1; }
            public function updateByKeys(array $keys, array $row): int { return 1; }
            public function upsertByKeys(array $row, array $keys, array $updateColumns = []): void {}
            public function deleteById(array|string|int $_): int { return 1; }
            public function restoreById(array|string|int $_): int { return 1; }
            public function findById(array|string|int $_, array $opts = []): ?array { $this->hits++; return ['id'=>1,'v'=>'x']; }
            public function findByIds(array $ids, array $opts = []): array { return [['id'=>1,'v'=>'x']]; }
            public function exists(int|string|array $id = 0, array $params = []): bool { return true; }
            public function count(string $whereSql = '1=1', array $params = []): int { return 1; }
            /** @param array<string,mixed>|object $criteria */
            public function paginate(mixed $criteria): array { return ['items'=>[],'total'=>0,'page'=>1,'perPage'=>10]; }
            public function paginateBySeek(object $criteria, array $order, ?array $cursor, int $limit): array { return ['items'=>[],'nextCursor'=>null]; }
            public function lockById(array|string|int $id, string $mode = 'wait', string $strength = 'update'): ?array { return null; }
            public function existsById(array|string|int $id): bool { return true; }
            public function getById(array|string|int $id, bool $asDto = false): array|null { return $this->findById($id); }
            public function getByUnique(array $keyValues, bool $asDto = false): array|null { return $this->findById(1); }
            public function setIngressAdapter(?object $adapter = null, ?string $table = null): void {}
            public function table(): string { return 'table-x'; }
            public function def(): string { return ''; }
        };
    }

    public function test_getById_cached_and_invalidated_on_write(): void
    {
        $db = DbUtil::db();
        $qc = new QueryCache(new ArrayCache(), null, null, 't:');
        /** @var object{hits:int}&\BlackCat\Database\Contracts\ContractRepository&GenericCrudRepositoryShape $repo */
        $repo = $this->makeRepo();

        $svc = new class($db, $repo, 'id', $qc) extends GenericCrudService {
            use ServiceHelpers; // provides db() and qcache()
            public function __construct(Database $db, \BlackCat\Database\Contracts\ContractRepository&GenericCrudRepositoryShape $repo, string $pk, QueryCache $qc) {
                parent::__construct($db,$repo,$pk,$qc,'table-x');
            }
        };

        // 1) first hit goes to the repository
        $r1 = $svc->getById(1);
        $this->assertSame(['id'=>1,'v'=>'x'], $r1);
        $this->assertSame(1, $repo->hits);

        // 2) second hit comes from cache
        $r2 = $svc->getById(1);
        $this->assertSame(1, $repo->hits, 'must be cache hit');

        // 3) update invalidates
        $svc->updateById(1, ['v'=>'y']);
        $r3 = $svc->getById(1);
        $this->assertSame(2, $repo->hits, 'cache must be invalidated after update');

        // 4) delete invalidates
        $svc->deleteById(1);
        $r4 = $svc->getById(1);
        $this->assertSame(3, $repo->hits);

        // 5) upsert with PK invalidates
        $svc->upsert(['id'=>1,'v'=>'z']);
        $r5 = $svc->getById(1);
        $this->assertSame(4, $repo->hits);
    }
}
