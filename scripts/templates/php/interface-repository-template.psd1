@{
  File   = 'src/Repository.php'
  Tokens = @('NAMESPACE','ENTITY_CLASS','DATABASE_FQN')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

use [[DATABASE_FQN]];
use [[NAMESPACE]]\Repository\[[ENTITY_CLASS]]Repository;
use [[NAMESPACE]]\Criteria;

/**
 * Umbrella/facade pro testy a tooly – drží stabilní FQN.
 */
final class Repository
{
    private [[ENTITY_CLASS]]Repository $repo;

    public function __construct(private Database $db)
    {
        $this->repo = new [[ENTITY_CLASS]]Repository($db);
    }

    public function insert(array $row): void { $this->repo->insert($row); }
    public function insertMany(array $rows): void { $this->repo->insertMany($rows); }

    public function upsert(array $row): void
    {
        if (method_exists($this->repo, 'upsert')) { $this->repo->upsert($row); }
        else { $this->repo->insert($row); }
    }

    public function updateById(int|string $id, array $row): int { return $this->repo->updateById($id, $row); }
    public function deleteById(int|string $id): int { return $this->repo->deleteById($id); }
    public function restoreById(int|string $id): int { return $this->repo->restoreById($id); }

    public function findById(int|string $id): ?array { return $this->repo->findById($id); }
    public function exists(string $whereSql = '1=1', array $params = []): bool { return $this->repo->exists($whereSql, $params); }
    public function count(string $whereSql = '1=1', array $params = []): int { return $this->repo->count($whereSql, $params); }

    /** @return array{items:array<int,array>,total:int,page:int,perPage:int} */
    public function paginate(Criteria $c): array { return $this->repo->paginate($c); }

    public function lockById(int|string $id): ?array { return $this->repo->lockById($id); }
}
'@
}
