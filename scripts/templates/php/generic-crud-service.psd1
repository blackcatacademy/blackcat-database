@{
  File   = 'src/Service/GenericCrudService.php'
  Tokens = @(
    'NAMESPACE'
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Service;

use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Services\GenericCrudService as BaseCrud;
use BlackCat\Database\Contracts\ContractRepository as RepoContract;
use [[NAMESPACE]]\Definitions;
use [[NAMESPACE]]\Criteria;
use [[NAMESPACE]]\Support\OperationResult;

/**
 * Lokální „tenký“ CRUD service:
 * - dědí globální BaseCrud a automaticky doplní PK, cache namespace a version column z Definitions
 * - zachovává původní API wrapperů s OperationResult (ale NEoverride-uje create() ani createAndFetch())
 * - přidává užitečné 2% helperů (existsById, optimistic update, withRowLock)
 *
 * @method array{id:int|string|null} create(array $row)                                   Zděděno z BaseCrud
 * @method array|null                createAndFetch(array $row, int $ttl = 0)             Zděděno z BaseCrud
 */
final class GenericCrudService extends BaseCrud
{
    public function __construct(
        Database $db,
        RepoContract $repo,
        ?QueryCache $qcache = null
    ) {
        $pk       = Definitions::pk();
        $cacheNs  = 'table-' . Definitions::table();
        $version  = Definitions::versionColumn();

        // Volitelný odhad PG sekvence pro lastInsertId(); v MySQL se ignoruje.
        $seqGuess = Definitions::isIdentityPk()
            ? (Definitions::table() . '_' . $pk . '_seq')
            : null;

        parent::__construct($db, $repo, $pk, $qcache, $cacheNs, $seqGuess, $version);
    }

    /** Alias na globální paginate – ponechává stejné API jako dřív.
     *  @return array{items:array<int,array>,total:int,page:int,perPage:int}
     */
    public function list(Criteria $c): array
    {
        return $this->paginate($c);
    }

    /** Wrapper, který vrátí OperationResult místo array. */
    public function createResult(array $row): OperationResult
    {
        $res = parent::create($row); // ['id'=>mixed|null]
        return OperationResult::ok($res);
    }

    /** Vloží a hned načte celý řádek, ale vrátí OperationResult. */
    public function createAndFetchResult(array $row, int $ttl = 0): OperationResult
    {
        $fetched = parent::createAndFetch($row, $ttl);
        return $fetched !== null
            ? OperationResult::ok(['row' => $fetched, 'id' => $fetched[Definitions::pk()] ?? null])
            : OperationResult::fail('Vytvoření se nezdařilo nebo nebylo možné přečíst zpět.');
    }

    public function update(int|string $id, array $row): OperationResult
    {
        $n = parent::updateById($id, $row);
        return $n > 0 ? OperationResult::ok(['affected' => $n]) : OperationResult::fail('Nenalezeno');
    }

    /** Optimistic locking – pokud Definitions nemá version column, provede běžný update. */
    public function updateOptimistic(int|string $id, array $row, int $expectedVersion): OperationResult
    {
        $n = Definitions::supportsOptimisticLocking()
            ? parent::updateByIdOptimistic($id, $row, $expectedVersion)
            : parent::updateById($id, $row);

        return $n > 0 ? OperationResult::ok(['affected' => $n]) : OperationResult::fail('Nenalezeno nebo konflikt verze');
    }

    public function delete(int|string $id): OperationResult
    {
        $n = parent::deleteById($id);
        return $n > 0 ? OperationResult::ok(['affected' => $n]) : OperationResult::fail('Nenalezeno');
    }

    public function restore(int|string $id): OperationResult
    {
        $n = parent::restoreById($id);
        return $n > 0 ? OperationResult::ok(['affected' => $n]) : OperationResult::fail('Nenalezeno');
    }

    public function get(int|string $id, int $ttl = 15): ?array
    {
        return $this->getById($id, $ttl);
    }

    public function existsById(int|string $id): bool
    {
        return parent::existsById($id);
    }

    /**
     * Proveď práci v jedné transakci s řádkovým zámkem (SELECT … FOR UPDATE).
     * $fn = function(array $lockedRow, Database $db): mixed
     */
    public function withRowLock(int|string $id, callable $fn): mixed
    {
        return parent::withRowLock($id, $fn);
    }
}
'@
}
