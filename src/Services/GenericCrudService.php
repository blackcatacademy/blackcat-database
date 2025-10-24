<?php
declare(strict_types=1);

namespace BlackCat\Database\Services;

use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Support\ServiceHelpers;

/**
 * 98% případů: CRUD nad jednou tabulkou s definicemi a repozitářem.
 * Očekává se kompatibilní generovaný Repository a Definitions v balíčku.
 */
final class GenericCrudService
{
    use ServiceHelpers;

    public function __construct(
        private Database $db,
        private object $repository,        // generovaný Repository (insert/updateById/...)
        private string $pkCol,             // např. 'id'
        private ?QueryCache $qcache = null,
        private ?string $cacheNs = null    // např. 'table-users'
    ) {}

    public function create(array $row): array
    {
        return $this->txn(function() use ($row) {
            $this->repository->insert($row);
            // pokud MySQL auto-inc, můžeš vrátit lastInsertId
            $id = $this->db()->lastInsertId();
            return ['id' => $id];
        });
    }

    public function upsert(array $row): void
    {
        $this->txn(fn() => $this->repository->upsert($row));
        $this->invalidateByPkIfPresent($row);
    }

    public function updateById(int|string $id, array $row): int
    {
        $n = $this->txn(fn()=> $this->repository->updateById($id, $row));
        $this->invalidatePk($id);
        return $n;
    }

    public function deleteById(int|string $id): int
    {
        $n = $this->txn(fn()=> $this->repository->deleteById($id));
        $this->invalidatePk($id);
        return $n;
    }

    public function restoreById(int|string $id): int
    {
        $n = $this->txn(fn()=> $this->repository->restoreById($id));
        $this->invalidatePk($id);
        return $n;
    }

    public function getById(int|string $id, int $ttl=15): ?array
    {
        if (!$this->qcache || !$this->cacheNs) {
            return $this->repository->findById($id);
        }
        $key = $this->idKey($this->cacheNs, (string)$id);
        return $this->qcache()->remember($key, $ttl, fn() => $this->repository->findById($id));
    }

    public function paginate(object $criteria): array
    {
        return $this->txnRO(fn()=> $this->repository->paginate($criteria));
    }

    private function invalidatePk(int|string $id): void
    {
        if ($this->qcache && $this->cacheNs) {
            $key = $this->idKey($this->cacheNs, (string)$id);
            try { $this->qcache()->remember($key, 0, fn()=>null); } catch (\Throwable $_) {}
            // PSR-16 nemá deleteByKeyPrefix: invalidace řešíme konkrétním klíčem
            try { $this->qcache?->cache()->delete($key); } catch (\Throwable $_) {}
        }
    }
    private function invalidateByPkIfPresent(array $row): void
    {
        if (!isset($row[$this->pkCol])) return;
        $this->invalidatePk((string)$row[$this->pkCol]);
    }
}
/*Pozn.: remember() vrací výsledek a zároveň hodnotu uloží – na explicitní delete() používáš PSR-16 cache přímo (máš ji v QueryCache dostupnou jako dependency, případně si do QueryCache přidej public function cache(): CacheInterface getter – nechávám na tobě).