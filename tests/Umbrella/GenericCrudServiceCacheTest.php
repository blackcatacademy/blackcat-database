<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Umbrella;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Services\GenericCrudService;
use BlackCat\Database\Support\ServiceHelpers;
use BlackCat\Database\Tests\Fakes\ArrayCache;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Tests\Util\DbUtil;

final class GenericCrudServiceCacheTest extends TestCase
{
    private function makeRepo(): object {
        return new class {
            public int $hits = 0;
            public function insert(array $_): void {}
            public function upsert(array $_): void {}
            public function updateById(int|string $_, array $__): int { return 1; }
            public function deleteById(int|string $_): int { return 1; }
            public function restoreById(int|string $_): int { return 1; }
            public function findById(int|string $_): ?array { $this->hits++; return ['id'=>1,'v'=>'x']; }
        };
    }

    public function test_getById_cached_and_invalidated_on_write(): void
    {
        $db = DbUtil::db();
        $qc = new QueryCache(new ArrayCache(), null, null, 't:');
        $repo = $this->makeRepo();

        $svc = new class($db, $repo, 'id', $qc) extends GenericCrudService {
            use ServiceHelpers; // zajistí db(), qcache()
            public function __construct($db,$repo,$pk,$qc) { parent::__construct($db,$repo,$pk,$qc,'table-x'); }
        };

        // 1) první hit jde do repo
        $r1 = $svc->getById(1);
        $this->assertSame(['id'=>1,'v'=>'x'], $r1);
        $this->assertSame(1, $repo->hits);

        // 2) druhý hit z cache
        $r2 = $svc->getById(1);
        $this->assertSame(1, $repo->hits, 'must be cache hit');

        // 3) update invaliduje
        $svc->updateById(1, ['v'=>'y']);
        $r3 = $svc->getById(1);
        $this->assertSame(2, $repo->hits, 'cache must be invalidated after update');

        // 4) delete invaliduje
        $svc->deleteById(1);
        $r4 = $svc->getById(1);
        $this->assertSame(3, $repo->hits);

        // 5) upsert s PK invaliduje
        $svc->upsert(['id'=>1,'v'=>'z']);
        $r5 = $svc->getById(1);
        $this->assertSame(4, $repo->hits);
    }
}
