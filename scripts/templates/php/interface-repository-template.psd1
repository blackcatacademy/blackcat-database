@{
  File   = 'src/Repository.php'
  Tokens = @('NAMESPACE','ENTITY_CLASS','DATABASE_FQN','DTO_CLASS')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

use [[DATABASE_FQN]] as Database;
use [[NAMESPACE]]\Repository\[[ENTITY_CLASS]]Repository;
use [[NAMESPACE]]\Criteria;
use BlackCat\Database\Contracts\KeysetRepository as KeysetRepoContract;

/**
 * Umbrella/facade for tests and tooling - keeps a stable FQN.
 */
final class Repository
{
    private [[ENTITY_CLASS]]Repository $repo;

    public function __construct(private Database $db)
    {
        $this->repo = new [[ENTITY_CLASS]]Repository($db);
    }

    /** Convenience Criteria factory bound to this Database (handles dialect and optional tenancy). */
    public function criteria(int|string|array|null $tenantId = null, string $tenantColumn = "tenant_id", bool $quoteIdentifiers = false): Criteria
    {
        return Criteria::fromDb($this->db, $tenantId, $tenantColumn, $quoteIdentifiers);
    }

    // --- Create/Upsert/Batch -------------------------------------------------

    public function insert(array $row): void { $this->repo->insert($row); }
    public function insertMany(array $rows): void { $this->repo->insertMany($rows); }

    public function upsert(array $row): void
    {
        if (method_exists($this->repo, 'upsert')) { $this->repo->upsert($row); }
        else { $this->repo->insert($row); }
    }

    /** Forwarder: upsert by business keys if the repository allows it, otherwise fallback. */
    public function upsertByKeys(array $row, array $keys, array $updateColumns = []): void
    {
        if (method_exists($this->repo, 'upsertByKeys')) {
            $this->repo->upsertByKeys($row, $keys, $updateColumns);
        } elseif (method_exists($this->repo, 'upsert')) {
            $this->repo->upsert($row);
        } else {
            $this->repo->insert($row);
        }
    }

    public function upsertMany(array $rows): void
    {
        if (method_exists($this->repo, 'upsertMany')) { $this->repo->upsertMany($rows); }
        else { foreach ($rows as $r) { $this->upsert((array)$r); } }
    }

    // --- Update/Delete/Restore ----------------------------------------------

    public function updateById(int|string|array $id, array $row): int { return $this->repo->updateById($id, $row); }
    public function deleteById(int|string|array $id): int { return $this->repo->deleteById($id); }
    public function restoreById(int|string|array $id): int { return $this->repo->restoreById($id); }

    // --- Read/Exists/Count ---------------------------------------------------

    public function findById(int|string|array $id): ?array { return $this->repo->findById($id); }
    public function exists(string $whereSql = '1=1', array $params = []): bool { return $this->repo->exists($whereSql, $params); }
    public function count(string $whereSql = '1=1', array $params = []): int { return $this->repo->count($whereSql, $params); }

    /** @return array{items:array<int,array>,total:int,page:int,perPage:int} */
    public function paginate(Criteria $c): array { return $this->repo->paginate($c); }

    /**
     * Keyset/seek pagination:
     * - delegates when the repository implements KeysetRepository
     * - otherwise falls back to the first page of classic pagination sized by $limit
     *
     * @param array{col:string,dir:'asc'|'desc',pk:string} $order
     * @param array{colValue:mixed,pkValue:mixed}|null $cursor
     * @return array{0:array<int,array<string,mixed>>,1:array{colValue:mixed,pkValue:mixed}|null}
     */
    public function paginateBySeek(Criteria $c, array $order, ?array $cursor, int $limit): array
    {
        if ($this->repo instanceof KeysetRepoContract) {
            return $this->repo->paginateBySeek($c, $order, $cursor, $limit);
        }
        $c2 = clone $c;
        $c2->page(1)->perPage(max(1, $limit));
        $page = $this->repo->paginate($c2);
        return [$page['items'] ?? [], null];
    }

    /** @return array<int,array<string,mixed>> */
    public function findAllByIds(array $ids): array { return $this->repo->findAllByIds($ids); }
    
    /** @return array<string,mixed>|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null */
    public function getByUnique(array $keys, bool $asDto = false): array|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null
    {
        return $this->repo->getByUnique($keys, $asDto);
    }

    /** @return array<string,mixed>|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null */
    public function getById(int|string|array $id, bool $asDto = false): array|\[[NAMESPACE]]\Dto\[[DTO_CLASS]]|null
    {
        return $this->repo->getById($id, $asDto);
    }

    /** @param 'wait'|'nowait'|'skip_locked' $mode  @param 'update'|'share' $strength */
    public function lockById(int|string|array $id, string $mode = 'wait', string $strength = 'update'): ?array {
        return $this->repo->lockById($id, $mode, $strength);
    }

        /** Upsert with revive (sets deleted_at=NULL when the table supports soft-delete). */
    public function upsertRevive(array $row): void
    {
        if (method_exists($this->repo, 'upsertRevive')) { $this->repo->upsertRevive($row); }
        else { $this->repo->upsert($row); }
    }

    /** Upsert by keys with revive behavior. */
    public function upsertByKeysRevive(array $row, array $keys, array $updateColumns = []): void
    {
        if (method_exists($this->repo, 'upsertByKeysRevive')) {
            $this->repo->upsertByKeysRevive($row, $keys, $updateColumns);
        } elseif (method_exists($this->repo, 'upsertByKeys')) {
            $this->repo->upsertByKeys($row, $keys, $updateColumns);
        } elseif (method_exists($this->repo, 'upsert')) {
            $this->repo->upsert($row);
        } else {
            $this->repo->insert($row);
        }
    }

    public function upsertManyRevive(array $rows): void
    {
        if (method_exists($this->repo, 'upsertManyRevive')) { $this->repo->upsertManyRevive($rows); }
        else { foreach ($rows as $r) { $this->upsertRevive((array)$r); } }
    }
}
'@
}
