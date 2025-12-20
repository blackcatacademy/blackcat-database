<?php
/*
 *       ####                                
 *      ######                              ██╗    ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗     
 *     #########                            ██║    ██║██╔════╝██║     ██╔════╝██╔═══██╗████╗ ████║██╔════╝ 
 *    ##########         ##                 ██║ █╗ ██║█████╗  ██║     ██║     ██║   ██║██╔████╔██║█████╗   
 *    ###########      ####                 ██║███╗██║██╔══╝  ██║     ██║     ██║   ██║██║╚██╔╝██║██╔══╝   
 * ###############   ######                 ╚███╔███╔╝███████╗███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║███████╗
 * ###########  ##  #######                  ╚══╝╚══╝ ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝ 
 * #########    ### #######                  
 * #########     ###  ####                   ██╗  ██╗███████╗██████╗  ██████╗ ██╗ ██████╗███████╗ 
 * ###########    ##    ##                   ██║  ██║██╔════╝██╔══██╗██╔═══██╗██║██╔════╝██╔════╝ 
 * ##########                #               ███████║█████╗  ██████╔╝██║   ██║██║██║     ███████╗ 
 * #######                     ##            ██╔══██║██╔══╝  ██╔══██╗██║   ██║██║██║     ╚════██║ 
 * ##                            ##          ██║  ██║███████╗██║  ██║╚██████╔╝██║╚██████╗███████║ 
 * ######              #######    ##         ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═════╝╚══════╝ 
 * #####            #######  ##   ##       ┌────────────────────────────────────────────────────────────────────────────┐  
 * #####               ####  ##    #         BLACK CAT DATABASE • Arcane Custody Notice                                 │
 * ########             #######    ##        © 2025 Black Cat Academy s. r. o. • All paws reserved.                     │
 * ####                        #     ##      Licensed strictly under the BlackCat Database Proprietary License v1.0.    │
 * ##########                          ##    Evaluation only; commercial rites demand written consent.                  │
 * ####           ######  #        ######    Unauthorized forks or tampering awaken enforcement claws.                  │
 * #####               ##  ##          ##    Reverse engineering, sublicensing, or origin stripping is forbidden.       │
 * ##########   ###  #### ####        #      Liability for lost data, profits, or familiars remains with the summoner.  │
 * ##                 ##  ##       ####      Infringements trigger termination; contact blackcatacademy@protonmail.com. │
 * ###########      ##   # #   ######        Leave this sigil intact—smudging whiskers invites spectral audits.         │
 * #########       #   ##          ##        Governed under the laws of the Slovak Republic.                            │
 * ##############                ###         Motto: “Purr, Persist, Prevail.”                                           │
 * #############    ###############       └─────────────────────────────────────────────────────────────────────────────┘
 */

declare(strict_types=1);

namespace BlackCat\Database\Services;

use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use BlackCat\Database\Contracts\ContractRepository as RepoContract;
use BlackCat\Database\Services\GenericCrudRepositoryShape;
use BlackCat\Database\Contracts\DatabaseIngressAdapterInterface;
use BlackCat\Database\Contracts\DatabaseIngressCriteriaAdapterInterface;
use BlackCat\Database\Crypto\IngressLocator;
use BlackCat\Database\Telemetry\CoverageTelemetryReporter;
use Closure;
use BlackCat\Database\Exceptions\OptimisticLockException;
use BlackCat\Database\Support\ServiceHelpers;
use BlackCat\Database\Support\SqlExpr;
use BlackCat\Database\Support\SqlIdentifier as Ident;

/**
 * GenericCrudService
 *
 * Lightweight, safe, developer-friendly CRUD service on top of a "duck-typed" repository.
 * - Strictly parameterized with an optional per-ID cache layer.
 * - Supports optimistic locking (natively from the repo or via row-lock fallback).
 * - Idempotent "first-write-wins" section with an advisory lock.
 * - Optional whitelist restricting which columns may be updated.
 *
 * Repository must implement at least: insert, updateById, deleteById, findById.
 * Recommended (used when present): exists, upsert, upsertByKeys,
 * updateByKeys, insertMany, findByIds, lockById, updateByIdOptimistic, updateByIdExpr.
 */
class GenericCrudService
{
    use ServiceHelpers;

    /** @phpstan-var RepoContract&GenericCrudRepositoryShape */
    protected RepoContract $repository;

    /** @var array<string,bool>|null map of whitelisted columns for update/upsert */
    private ?array $updatableColsWhitelist = null;
    protected ?DatabaseIngressAdapterInterface $ingressAdapter = null;
    protected ?string $ingressTable = null;

    /**
     * @param RepoContract&GenericCrudRepositoryShape $repository
     */
    public function __construct(
        protected Database $db,
        RepoContract $repository,            // ContractRepository with optional extras
        private string $pkCol,               // e.g. 'id'
        private ?QueryCache $qcache = null,  // per-ID cache
        private ?string $cacheNs = null,     // e.g. 'table-users'
        private ?string $pgSequence = null,  // PG sequence for lastInsertId()
        private ?string $versionCol = null,  // optimistic locking column (e.g. 'version')
        private int $retryAttempts = 3       // default retry budget for withRowLock()
    ) {
        $this->repository = $repository;
        $this->assertRepositoryShape($this->repository);
        $this->retryAttempts = \max(1, $this->retryAttempts);
        if ($this->pkCol === '') {
            throw new \InvalidArgumentException('Primary key column name must not be empty.');
        }

        CoverageTelemetryReporter::register();
        $this->ingressAdapter = IngressLocator::adapter();
        $this->ingressTable = $this->detectRepositoryTable();
        $this->propagateIngressAdapter();
    }

    // ----------------------- Public API -----------------------

    public function withIngressAdapter(?DatabaseIngressAdapterInterface $adapter, ?string $table = null): self
    {
        $this->ingressAdapter = $adapter;
        if (\is_string($table) && $table !== '') {
            $this->ingressTable = $table;
        } elseif ($this->ingressTable === null) {
            $this->ingressTable = $this->detectRepositoryTable();
        }

        $this->propagateIngressAdapter();
        return $this;
    }

    /**
     * Allowed columns for update/upsert (all other keys will be rejected).
     * @param list<string> $cols
     */
    public function withUpdatableColumns(array $cols): self
    {
        $map = [];
        foreach ($cols as $c) {
            $c = (string)$c;
            if ($c !== '') { $map[$c] = true; }
        }
        $this->updatableColsWhitelist = $map ?: null;
        return $this;
    }

    public function getIngressAdapter(): ?DatabaseIngressAdapterInterface
    {
        return $this->ingressAdapter;
    }

    /** @return array{id:int|string|array|null} */
    public function create(#[\SensitiveParameter] array $row): array
    {
        return $this->txn(function () use ($row) {
            $this->repository->insert($row);

            $id = $row[$this->pkCol] ?? null;
            if ($id === null) {
                try {
                    $seq = $this->pgSequence ?: null;
                    $raw = $this->db()->lastInsertId($seq);
                    $id  = ($raw === '' ? null : $raw);
                } catch (\Throwable) { /* ignore */ }
            }
            if ($id !== null) { $this->invalidatePk($id); }
            $this->invalidateNamespace();
            return ['id' => $id];
        });
    }

    public function createAndFetch(#[\SensitiveParameter] array $row, int|\DateInterval|null $ttl = null): ?array
    {
        $res = $this->create($row);
        $id  = $res['id'] ?? null;
        if ($id === null) { return null; }

        // After create always fetch fresh data without cache (defaults/triggers may populate values)
        $fresh = $this->repository->findById($id);

        // If the caller explicitly supplied TTL, warm it into cache
        if ($fresh !== null && $ttl !== null && $this->qcache && $this->cacheNs) {
            $key = $this->idKey($this->cacheNs, $this->idKeyFor($id));
            $this->qcache->remember($key, $ttl, static fn() => $fresh);
        }
        return $fresh;
    }

    public function upsert(#[\SensitiveParameter] array $row): void
    {
        // TODO(crypto-integrations): Delegate inserts/updates to the DatabaseIngressAdapter
        // so rows hit manifest-defined encryption before repository->insert/update is called.
        $this->txn(function () use ($row) {
            if (\method_exists($this->repository, 'upsert')) {
                $this->repository->upsert($row);
                return;
            }

            $pk = $this->pkCol;
            if (\array_key_exists($pk, $row) && $row[$pk] !== null) {
                $id = $row[$pk];

            $exists = \method_exists($this->repository, 'exists')
                ? (function () use ($pk, $id): bool {
                    $cond = \BlackCat\Database\Support\SqlIdentifier::q($this->db(), $pk) . ' = :id';
                    /** @var non-empty-string $cond */
                    $cond = $cond;
                    return (bool)$this->repository->exists($cond, [':id' => $id]);
                })()
                : ($this->repository->findById($id) !== null);

                if ($exists) {
                    $update = $row; unset($update[$pk]);
                    $this->assertKnownKeys($update);
                    if ($update) { $this->repository->updateById($id, $update); }
                } else {
                    $this->repository->insert($row);
                }
            } else {
                $this->repository->insert($row);
            }
        });

        $this->invalidateByPkIfPresent($row);
        $this->invalidateNamespace();
    }

    /**
     * Upsert based on business keys (no duplicate inserts).
     * @param array<string,mixed> $row
     * @param array<string,mixed> $keys
     * @param list<string>        $updateCols
     */
    public function upsertByKeys(#[\SensitiveParameter] array $row, array $keys, array $updateCols = []): void
    {
        $keysForQuery = $keys;
        $table = $this->ingressTable ?? $this->detectRepositoryTable();
        if (
            $table !== null
            && $this->ingressAdapter instanceof DatabaseIngressCriteriaAdapterInterface
            && $keysForQuery !== []
        ) {
            $keysForQuery = $this->ingressAdapter->criteria($table, $keysForQuery);
        }

        $this->txn(function () use ($row, $keys, $keysForQuery, $updateCols) {
            if (\method_exists($this->repository, 'upsertByKeys')) {
                $this->assertKnownKeys($row);
                $this->repository->upsertByKeys($row, $keysForQuery, $updateCols);
                return;
            }

            $where = []; $params = [];
            foreach ($keysForQuery as $k => $v) {
                $qi = Ident::qi($this->db(), (string)$k);
                $p  = ':k_' . \preg_replace('~\W~', '_', (string)$k);
                $where[] = "{$qi} = {$p}";
                $params[$p] = $v;
            }
            $cond = \implode(' AND ', $where);
            if ($cond === '') {
                $cond = '1=1';
            }
            /** @var non-empty-string $cond */
            $cond = $cond;

            $exists = \method_exists($this->repository, 'exists')
                ? (bool)$this->repository->exists($cond, $params)
                : false;

            if ($exists) {
                $update = $row;
                foreach (\array_keys($keys) as $k) { unset($update[$k]); }
                $this->assertKnownKeys($update);

                if (!$updateCols && $update) {
                    if (\method_exists($this->repository, 'updateByKeys')) {
                        $this->repository->updateByKeys($keysForQuery, $update);
                        return;
                    }
                    $pk = $this->pkCol;
                    if (\array_key_exists($pk, $keys)) {
                        $this->repository->updateById($keys[$pk], $update);
                    } else {
                        throw new \RuntimeException('upsertByKeys fallback requires updateByKeys() or PK present in keys');
                    }
                } else {
                    $subset = \array_intersect_key($row, \array_flip($updateCols));
                    $this->assertKnownKeys($subset);
                    if (\method_exists($this->repository, 'updateByKeys')) {
                        $this->repository->updateByKeys($keysForQuery, $subset);
                    } else {
                        $pk = $this->pkCol;
                        if (\array_key_exists($pk, $keys)) {
                            $this->repository->updateById($keys[$pk], $subset);
                        } else {
                            throw new \RuntimeException('upsertByKeys fallback requires updateByKeys() or PK present in keys');
                        }
                    }
                }
            } else {
                $this->repository->insert($row);
            }
        });

        $this->invalidateByPkIfPresent($row);
        $this->invalidateNamespace();
    }

    /**
     * @param int|string|array $id
     * @param array<string,mixed> $row
     */
    public function updateById(int|string|array $id, #[\SensitiveParameter] array $row): int
    {
        $this->assertKnownKeys($row);
        $n = $this->txn(fn() => $this->repository->updateById($id, $row));
        $this->invalidatePk($id);
        $this->invalidateNamespace();
        return $n;
    }

    /**
     * Optimistic locking variant – prefers native repo support, otherwise falls back.
     * @param int|string|array $id
     * @param array<string,mixed> $row
     */
    public function updateByIdOptimistic(int|string|array $id, #[\SensitiveParameter] array $row, int $expectedVersion): int
    {
        if ($this->versionCol === null) {
            return $this->updateById($id, $row);
        }

        // Prefer repository-native optimistic update if available
        if (\method_exists($this->repository, 'updateByIdOptimistic')) {
            $this->assertKnownKeys($row);
            $n = $this->txn(fn() => $this->repository->updateByIdOptimistic($id, $row, $expectedVersion));
            if ($n !== 1) {
                throw new OptimisticLockException('Optimistic lock failed (stale version).');
            }
            $this->invalidatePk($id);
            return $n;
        }

        // Fallback: lock row, compare version, then update with increment
        return (int)$this->withRowLock($id, function (?array $locked) use ($row, $expectedVersion, $id) {
            if ($this->versionCol === null || $locked === null || !\array_key_exists($this->versionCol, $locked)) {
                throw new OptimisticLockException('Optimistic lock failed (row not found).');
            }
            $current = (int)$locked[$this->versionCol];
            if ($current !== $expectedVersion) {
                throw new OptimisticLockException('Optimistic lock failed (stale version).');
            }
            $payload = $row;
            $payload[$this->versionCol] = $expectedVersion + 1;
            $this->assertKnownKeys($payload);

            $n = $this->repository->updateById($id, $payload);
            if ($n !== 1) {
                throw new OptimisticLockException('Optimistic lock update affected unexpected row count.');
            }
            $this->invalidatePk($id);
            return $n;
        }, 'wait');
    }

    public function updateByIdWithRetry(int|string|array $id, #[\SensitiveParameter] array $row, int $attempts = 3): int
    {
        return $this->retry($attempts, fn() => $this->updateById($id, $row));
    }

    public function deleteById(int|string|array $id): int
    {
        $n = $this->txn(fn() => $this->repository->deleteById($id));
        $this->invalidatePk($id);
        $this->invalidateNamespace();
        return $n;
    }

    public function restoreById(int|string|array $id): int
    {
        if (!\method_exists($this->repository, 'restoreById')) {
            return 0;
        }
        $n = $this->txn(fn() => $this->repository->restoreById($id));
        $this->invalidatePk($id);
        $this->invalidateNamespace();
        return $n;
    }

    public function getById(int|string|array $id, int|\DateInterval $ttl = 15): ?array
    {
        if (!$this->qcache || !$this->cacheNs) {
            return $this->repository->findById($id);
        }
        $key = $this->idKey($this->cacheNs, $this->idKeyFor($id));
        return $this->qcache->remember($key, $ttl, fn() => $this->repository->findById($id));
    }

    public function existsById(int|string|array $id): bool
    {
        if (\is_array($id)) {
            return $this->repository->findById($id) !== null;
        }
        if (\method_exists($this->repository, 'exists')) {
            $col = Ident::qi($this->db(), $this->pkCol);
            return (bool)$this->repository->exists("{$col} = :id", [':id' => $id]);
        }
        return $this->repository->findById($id) !== null;
    }

    /**
     * Fetch a single row/DTO by unique keys.
     *
     * If an ingress adapter with deterministic criteria support is configured,
     * keys are transformed before calling into the repository.
     *
     * @param array<string,mixed> $keys
     * @return array<string,mixed>|object|null
     */
    public function getByUnique(#[\SensitiveParameter] array $keys, bool $asDto = false): array|object|null
    {
        if (!\method_exists($this->repository, 'getByUnique')) {
            throw new \LogicException('Repository does not support getByUnique()');
        }

        $keysForQuery = $keys;
        $table = $this->ingressTable ?? $this->detectRepositoryTable();
        if (
            $table !== null
            && $this->ingressAdapter instanceof DatabaseIngressCriteriaAdapterInterface
            && $keysForQuery !== []
        ) {
            $keysForQuery = $this->ingressAdapter->criteria($table, $keysForQuery);
        }

        try {
            $rm = new \ReflectionMethod($this->repository, 'getByUnique');
            $row = ($rm->getNumberOfParameters() >= 2)
                ? $this->repository->getByUnique($keysForQuery, $asDto)
                : $this->repository->getByUnique($keysForQuery);
        } catch (\Throwable) {
            /** @var mixed $row */
            $row = $this->repository->getByUnique($keysForQuery, $asDto);
        }

        return is_array($row) || is_object($row) ? $row : null;
    }

    /**
     * Existence check by key/value pairs (composite unique keys, business keys, etc.).
     *
     * When a deterministic ingress adapter is configured, the keys are transformed
     * (e.g. HMAC) before the existence query is executed.
     *
     * @param array<string,mixed> $keys
     */
    public function existsByKeys(#[\SensitiveParameter] array $keys): bool
    {
        if ($keys === []) {
            throw new \InvalidArgumentException('existsByKeys() requires non-empty keys.');
        }

        $keysForQuery = $keys;
        $table = $this->ingressTable ?? $this->detectRepositoryTable();
        if (
            $table !== null
            && $this->ingressAdapter instanceof DatabaseIngressCriteriaAdapterInterface
            && $keysForQuery !== []
        ) {
            $keysForQuery = $this->ingressAdapter->criteria($table, $keysForQuery);
        }

        $where = [];
        $params = [];
        foreach ($keysForQuery as $k => $v) {
            $qi = Ident::qi($this->db(), (string)$k);

            if ($v === null) {
                $where[] = "{$qi} IS NULL";
                continue;
            }

            $p = ':k_' . \preg_replace('~\\W~', '_', (string)$k);
            $where[] = "{$qi} = {$p}";
            $params[$p] = $v;
        }

        $cond = \implode(' AND ', $where);
        if ($cond === '') {
            throw new \InvalidArgumentException('existsByKeys() produced an empty WHERE condition.');
        }

        /** @var non-empty-string $cond */
        $cond = $cond;
        return (bool)$this->repository->exists($cond, $params);
    }

    /**
     * @return array{items:list<array<string,mixed>>,total:int,page:int,perPage:int}
     */
    public function paginate(object $criteria): array
    {
        return $this->txnRO(fn() => $this->repository->paginate($criteria));
    }

    /**
     * Run the work inside a single transaction with a row lock.
     * $fn = function(?array $lockedRow, Database $db): mixed
     *
     * @param int|string|array $id
     */
    public function withRowLock(int|string|array $id, callable $fn, string $mode = 'wait'): mixed
    {
        $mode = \strtolower($mode);
        if (!\in_array($mode, ['wait','skip_locked','nowait'], true)) {
            $mode = 'wait';
        }
        return $this->retry($this->retryAttempts, function () use ($id, $fn, $mode) {
            return $this->txn(function () use ($id, $fn, $mode) {
                if (!\method_exists($this->repository, 'lockById')) {
                    $row = $this->repository->findById($id);
                    return $fn($row, $this->db());
                }

                try {
                    $rm = new \ReflectionMethod($this->repository, 'lockById');
                    $row = ($rm->getNumberOfParameters() >= 2)
                        ? $this->repository->lockById($id, $mode)
                        : $this->repository->lockById($id);
                } catch (\Throwable) {
                    $row = $this->repository->lockById($id);
                }

                if ($mode === 'skip_locked' && $row === null) {
                    return null;
                }
                return $fn($row, $this->db());
            });
        });
    }

    public function setRetryAttempts(int $n): void
    {
        $this->retryAttempts = \max(1, $n);
    }

    private function detectRepositoryTable(): ?string
    {
        if (\is_string($this->ingressTable) && $this->ingressTable !== '') {
            return $this->ingressTable;
        }

        $repo = $this->repository;
        if (!\is_object($repo)) {
            return null;
        }

        if (\method_exists($repo, 'table')) {
            try {
                /** @var mixed $table */
                $table = $repo->table();
                if (\is_string($table) && $table !== '') {
                    return $table;
                }
            } catch (\Throwable) {
                // ignore
            }
        }

        if (\method_exists($repo, 'def')) {
            try {
                /** @var mixed $fqn */
                $fqn = $repo->def();
                if (\is_string($fqn) && $fqn !== '' && \class_exists($fqn) && \method_exists($fqn, 'table')) {
                    /** @var mixed $table */
                    $table = $fqn::table();
                    if (\is_string($table) && $table !== '') {
                        return $table;
                    }
                }
            } catch (\Throwable) {
                // ignore
            }
        }

        return null;
    }

    private function propagateIngressAdapter(): void
    {
        $repo = $this->repository;
        if (!\is_object($repo) || !\method_exists($repo, 'setIngressAdapter')) {
            return;
        }

        $table = $this->ingressTable ?? $this->detectRepositoryTable();
        try {
            $repo->setIngressAdapter($this->ingressAdapter, $table);
        } catch (\Throwable) {
            // best-effort
        }
    }

    /** @param list<array<string,mixed>> $rows */
    public function insertMany(#[\SensitiveParameter] array $rows): void
    {
        $this->txn(function () use ($rows) {
            if (\method_exists($this->repository, 'insertMany')) {
                $this->repository->insertMany($rows);
            } else {
                foreach ($rows as $r) { $this->repository->insert($r); }
            }
        });
        $this->invalidateNamespace();
    }

    /**
     * Batch fetch by IDs (uses per-ID cache when enabled).
     * @param list<int|string|array> $ids
     * @return list<array<string,mixed>>
     */
    public function getByIds(array $ids, int|\DateInterval $ttl = 15): array
    {
        if (!$ids) return [];

        // If there is no cache and the repo supports findByIds, call it once.
        if ((!$this->qcache || !$this->cacheNs) && \method_exists($this->repository, 'findByIds')) {
            /** @var list<array<string,mixed>> $rows */
            $rows = (array)$this->repository->findByIds($ids);
            return $rows;
        }

        $rows = [];
        foreach ($ids as $id) {
            if ($this->qcache && $this->cacheNs) {
                $key = $this->idKey($this->cacheNs, $this->idKeyFor($id));
                $val = $this->qcache->remember($key, $ttl, fn() => $this->repository->findById($id));
                if ($val !== null) { $rows[] = $val; }
            } else {
                $val = $this->repository->findById($id);
                if ($val !== null) { $rows[] = $val; }
            }
        }
        return $rows;
    }

    /**
     * Variant that returns a map [id] => row.
     * @param list<int|string|array> $ids
     * @return array<int|string,array<string,mixed>>
     */
    public function getByIdsMap(array $ids, int|\DateInterval $ttl = 15): array
    {
        $list = $this->getByIds($ids, $ttl);
        $out  = [];
        foreach ($list as $r) {
            if (isset($r[$this->pkCol])) {
                /** @var int|string $k */
                $k = $r[$this->pkCol];
                $out[$k] = $r;
            }
        }
        return $out;
    }

    /** Fast bump of updated_at (prefer DB-side expression). */
    public function touchById(int|string|array $id, string $column = 'updated_at'): int
    {
        if (\method_exists($this->repository, 'updateByIdExpr')) {
            $expr = 'CURRENT_TIMESTAMP(6)';
            $n = $this->txn(fn() => $this->repository->updateByIdExpr($id, [$column => new SqlExpr($expr)]));
        } else {
            // Fallback – let the application supply the timestamp (UTC)
            $n = $this->txn(fn() => $this->repository->updateById(
                $id,
                [$column => (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s.u')]
            ));
        }
        if ($n) { $this->invalidatePk($id); }
        return $n;
    }

    /**
     * Idempotent section: "first write wins" (advisory lock + atomic INSERT, no races).
     * Tabulka: idempotency_keys(k PRIMARY KEY, expires_at timestamptz/datetime, payload json/jsonb/text)
     */
    public function idempotent(string $key, callable $fn, int $ttlSec = 3600): mixed
    {
        $ttlSec = \max(1, $ttlSec);
        return $this->withLock('idem:' . $key, 5, function () use ($key, $fn, $ttlSec) {
            return $this->txn(function () use ($key, $fn, $ttlSec) {
                $tbl = Ident::q($this->db(), 'idempotency_keys');

                // 1) quick hit
                $existing = $this->db()->fetchValue(
                    "SELECT payload FROM {$tbl} WHERE k = :k AND expires_at > CURRENT_TIMESTAMP",
                    [':k' => $key],
                    null
                );
                if ($existing !== null) {
                    return \json_decode((string)$existing, true);
                }

                // 2) produce and store (first write wins – we are under the lock)
                $res = $fn($this);
                $payload = \json_encode($res, \JSON_UNESCAPED_UNICODE|\JSON_UNESCAPED_SLASHES);

                if ($this->db()->isPg()) {
                    $sql = "INSERT INTO {$tbl}(k, expires_at, payload)
                            VALUES (:k, CURRENT_TIMESTAMP(6) + make_interval(secs => :ttl), :p)
                            ON CONFLICT (k) DO UPDATE
                               SET expires_at = EXCLUDED.expires_at
                               ,   payload    = {$tbl}.payload"; // keep the original payload (first write wins)
                    $this->db()->execute($sql, [':k'=>$key, ':ttl'=>$ttlSec, ':p'=>$payload]);
                } else {
                    // MySQL/MariaDB – alias variant (MySQL ≥ 8.0.20) + fallback to VALUES() (MariaDB, older MySQL)
                    $params = [':k' => $key, ':ttl' => $ttlSec, ':p' => $payload];

                    $ver     = $this->db()->serverVersion();
                    $useAlias = $ver !== null && version_compare($ver, '8.0.20', '>=');

                    $sqlAlias = "INSERT INTO {$tbl}(k, expires_at, payload)
                                 VALUES (:k, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL :ttl SECOND), :p) AS new
                                 ON DUPLICATE KEY UPDATE
                                     expires_at = new.expires_at,
                                     payload    = payload";

                    $sqlValues = "INSERT INTO {$tbl}(k, expires_at, payload)
                                  VALUES (:k, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL :ttl SECOND), :p)
                                  ON DUPLICATE KEY UPDATE
                                      expires_at = VALUES(expires_at),
                                      payload    = payload";

                    if ($useAlias) {
                        try {
                            $this->db()->execute($sqlAlias, $params);
                        } catch (\Throwable) {
                            $this->db()->execute($sqlValues, $params); // fallback for MariaDB/older MySQL
                        }
                    } else {
                        $this->db()->execute($sqlValues, $params);
                    }
                }

                return $res;
            });
        });
    }

    // ----------------------- Cache helpers -----------------------

    protected function invalidatePk(int|string|array $id): void
    {
        if (!$this->qcache || !$this->cacheNs) return;
        $key = $this->idKey($this->cacheNs, $this->idKeyFor($id));
        try { $this->qcache->delete($key); } catch (\Throwable) { /* best-effort */ }
        try {
            $inner = $this->qcache->cache();
            if ($inner !== null) {
                $inner->delete($key);
            }
        } catch (\Throwable) {}
    }

    protected function invalidateNamespace(): void
    {
        if ($this->qcache && $this->cacheNs) {
            $this->qcache->invalidatePrefix($this->cacheNs);
        }
    }

    protected function invalidateByPkIfPresent(array $row): void
    {
        if (\array_key_exists($this->pkCol, $row)) {
            $this->invalidatePk($row[$this->pkCol]);
        }
    }

    // ----------------------- Internals -----------------------

    private function assertRepositoryShape(RepoContract $r): void
    {
        foreach (['insert', 'updateById', 'deleteById', 'findById'] as $m) {
            if (!\method_exists($r, $m)) {
                throw new \InvalidArgumentException("Repository missing required method: {$m}()");
            }
        }
    }

    /** @param array<string,mixed> $row */
    private function assertKnownKeys(array $row): void
    {
        if ($this->updatableColsWhitelist === null) { return; }
        foreach ($row as $k => $_) {
            if (!isset($this->updatableColsWhitelist[$k])) {
                throw new \InvalidArgumentException("Unknown or disallowed column '{$k}' in update payload");
            }
        }
    }

    private function idKeyFor(mixed $id): string
    {
        if (\is_array($id)) {
            $norm = $id;
            // If associative, stabilize key order
            if (\array_keys($norm) !== \range(0, \count($norm) - 1)) { \ksort($norm); }
            $encoded = \json_encode($norm, \JSON_UNESCAPED_UNICODE|\JSON_UNESCAPED_SLASHES) ?: '';
            return 'ck:' . \hash('sha256', $encoded);
        }
        return (string)$id;
    }
}
