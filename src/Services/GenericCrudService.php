<?php
declare(strict_types=1);

namespace BlackCat\Database\Services;

use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Support\ServiceHelpers;

/**
 * Lehká univerzální CRUD služba nad jedním repozitářem.
 * - transakce/RO transakce přes ServiceHelpers
 * - volitelný QueryCache (per-ID)
 * - bezpečné typy (repo = ContractRepository)
 */
class GenericCrudService
{
    use ServiceHelpers;

    /**
     * @param Database        $db
     * @param object          $repository  Duck-typed ContractRepository (musí mít insert/updateById/… viz assertRepositoryShape()).
     * @param string          $pkCol       Název PK sloupce (např. 'id').
     * @param QueryCache|null $qcache      Volitelný cache wrapper.
     * @param string|null     $cacheNs     Namespace pro cache klíče (např. 'table-users').
     * @param string|null     $pgSequence  Volitelně název PG sekvence pro lastInsertId().
     * @param string|null     $versionCol  Volitelně název verze pro optimistic locking.
     */
    public function __construct(
        protected Database $db,
        private object $repository,
        private string $pkCol,
        private ?QueryCache $qcache = null,
        private ?string $cacheNs = null,
        private ?string $pgSequence = null,
        private ?string $versionCol = null
    ) {
        $this->assertRepositoryShape($this->repository);
    }

    /**
     * Umožní testům předat anonymní (duck-typed) repozitář,
     * ale v runtime zkontroluje, že má požadované metody.
     */
    private function assertRepositoryShape(object $r): void
    {
        // Vyžaduj jen metody, které používáme vždy.
        foreach (['insert','updateById','deleteById','restoreById','findById'] as $m) {
            if (!method_exists($r, $m)) {
                throw new \InvalidArgumentException("Repository missing required method: {$m}()");
            }
        }
        // Ostatní (upsert/exists/insertMany/paginate/lockById) kontrolujeme až při volání,
        // nebo máme fallback (viz upsert()).
    }

    /** @return array{id:int|string|null} */
    public function create(array $row): array
    {
        return $this->txn(function () use ($row) {
            $this->repository->insert($row);

            // 1) PK dodané v $row (např. UUID) má přednost
            $id = $row[$this->pkCol] ?? null;

            // 2) Pokus o získání ID z driveru (MySQL/PG)
            if ($id === null) {
                try {
                    // pro PG lze volitelně dodat název sekvence
                    $raw = $this->db()->lastInsertId($this->pgSequence ?? '');
                    $id  = ($raw === '' ? null : $raw);
                } catch (\Throwable) {
                    // některé drivy lastInsertId nepodporují – toleruj
                }
            }

            if ($id !== null) {
                // nově vytvořený řádek – případný stale cache pro jistotu pryč
                $this->invalidatePk((string)$id);
            }
            return ['id' => $id];
        });
    }

    /** Vloží a hned načte z DB (pokud známe ID). */
    public function createAndFetch(array $row, int $ttl = 0): ?array
    {
        $res = $this->create($row);
        $id  = $res['id'] ?? null;
        return $id !== null ? $this->getById($id, $ttl) : null;
    }

    public function upsert(array $row): void
    {
        $this->txn(function () use ($row) {
            if (method_exists($this->repository, 'upsert')) {
                $this->repository->upsert($row);
                return;
            }

            // Fallback bez exists(): když máme PK v $row, rozhodneme podle findById()
            $pk = $this->pkCol;
            if (array_key_exists($pk, $row) && $row[$pk] !== null) {
                $id = $row[$pk];

                $exists = method_exists($this->repository, 'exists')
                    ? (bool)$this->repository->exists($pk . ' = :id', [':id' => $id])
                    : ($this->repository->findById($id) !== null);

                if ($exists) {
                    $update = $row;
                    unset($update[$pk]);
                    if ($update) {
                        $this->repository->updateById($id, $update);
                    }
                } else {
                    $this->repository->insert($row);
                }
            } else {
                // Bez PK prostě vlož
                $this->repository->insert($row);
            }
        });

        $this->invalidateByPkIfPresent($row);
    }

    public function updateById(int|string $id, array $row): int
    {
        $n = $this->txn(fn() => $this->repository->updateById($id, $row));
        $this->invalidatePk($id);
        return $n;
    }

    /** Update s optimistic locking – očekává název verze v konstruktoru. */
    public function updateByIdOptimistic(int|string $id, array $row, int $expectedVersion): int
    {
        if ($this->versionCol) {
            $row[$this->versionCol] = $expectedVersion;
        }
        return $this->updateById($id, $row);
    }

    /** Update s automatickým retry (deadlock/serialization). */
    public function updateByIdWithRetry(int|string $id, array $row, int $attempts = 3): int
    {
        return $this->retry($attempts, fn() => $this->updateById($id, $row));
    }

    public function deleteById(int|string $id): int
    {
        $n = $this->txn(fn() => $this->repository->deleteById($id));
        $this->invalidatePk($id);
        return $n;
    }

    public function restoreById(int|string $id): int
    {
        $n = $this->txn(fn() => $this->repository->restoreById($id));
        $this->invalidatePk($id);
        return $n;
    }

    public function getById(int|string $id, int $ttl = 15): ?array
    {
        if (!$this->qcache || !$this->cacheNs) {
            return $this->repository->findById($id);
        }
        $key = $this->idKey($this->cacheNs, (string)$id);
        return $this->qcache->remember($key, $ttl, fn() => $this->repository->findById($id));
    }

    public function existsById(int|string $id): bool
    {
        return $this->repository->exists($this->pkCol . ' = :id', [':id' => $id]);
    }

    /** @return array{items:array<int,array>,total:int,page:int,perPage:int} */
    public function paginate(object $criteria): array
    {
        return $this->txnRO(fn() => $this->repository->paginate($criteria));
    }

    /**
     * Spusť práci v jedné transakci s řádkovým zámkem (SELECT … FOR UPDATE).
     * $fn = function(array $lockedRow, Database $db): mixed
     */
    public function withRowLock(int|string $id, callable $fn): mixed
    {
        return $this->txn(function () use ($id, $fn) {
            $row = $this->repository->lockById($id);
            if (!$row) {
                throw new \RuntimeException("Row {$id} not found for lock.");
            }
            return $fn($row, $this->db());
        });
    }

    /** ------ interní/rozšiřitelné pomocníky ------ */

    /** Umožni potomkům čistit cache ručně. */
    protected function invalidatePk(int|string $id): void
    {
        if (!$this->qcache || !$this->cacheNs) return;
        $key = $this->idKey($this->cacheNs, (string)$id);

        // best-effort invalidace (QueryCache + PSR-16, pokud je k dispozici)
        try { $this->qcache->remember($key, -1, fn() => null); } catch (\Throwable) {
            try { $this->qcache->remember($key, 0, fn() => null); } catch (\Throwable) {}
        }
        try {
            if (method_exists($this->qcache, 'cache') && $this->qcache->cache()) {
                $this->qcache->cache()->delete($key);
            }
        } catch (\Throwable) {}
    }

    protected function invalidateByPkIfPresent(array $row): void
    {
        if (array_key_exists($this->pkCol, $row)) {
            $this->invalidatePk((string)$row[$this->pkCol]);
        }
    }
    public function insertMany(array $rows): void
    {
        $this->txn(function () use ($rows) {
            if (method_exists($this->repository, 'insertMany')) {
                $this->repository->insertMany($rows);
            } else {
                foreach ($rows as $r) {
                    $this->repository->insert($r);
                }
            }
        });
    }
}
