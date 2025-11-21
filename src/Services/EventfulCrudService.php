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
use BlackCat\Database\Events\CrudEvent;
use BlackCat\Database\Events\CrudEventDispatcher;
use BlackCat\Database\Events\NullCrudEventDispatcher;
use BlackCat\Database\Exceptions\OptimisticLockException;
use BlackCat\Database\Outbox\OutboxRecord;
use BlackCat\Database\Outbox\OutboxRepository;
use BlackCat\Database\Support\OperationResult;
use BlackCat\Database\Support\Retry;
use BlackCat\Database\Support\ServiceHelpers;
use BlackCat\Database\Support\Telemetry;

/**
 * EventfulCrudService
 *
 * Drop-in replacement for GenericCrudService that emits CrudEvent events,
 * wraps mutations with retry logic, and can mirror into a SQL outbox.
 *
 * Safety & DX:
 * - All payloads are marked as #[\SensitiveParameter].
 * - Events are sent best-effort (the dispatcher MUST NOT throw).
 * - Outbox mirror uses OutboxRecord::fromCrudEvent (no manual JSON concatenation).
 * - Robust table/pk detection (caching + careful reflection) with extra metadata.
 */
class EventfulCrudService extends GenericCrudService
{
    use ServiceHelpers;

    private ?CrudEventDispatcher $dispatcher;
    private ?OutboxRepository $outbox;

    /** cache pro reflexi */
    private ?string $cachedPk = null;
    private ?string $cachedTable = null;

    public function __construct(
        Database $db,
        RepoContract&GenericCrudRepositoryShape $repo,
        ?QueryCache $qcache = null,
        ?CrudEventDispatcher $dispatcher = null,
        ?OutboxRepository $outbox = null
    ) {
        $pk         = $this->pk();
        $cacheNs    = $this->cacheNamespace();
        $versionCol = $this->versionColumn();

        parent::__construct(
            db: $db,
            repository: $repo,
            pkCol: $pk,
            qcache: $qcache,
            cacheNs: $cacheNs,
            versionCol: $versionCol
        );
        $this->dispatcher = $dispatcher ?? NullCrudEventDispatcher::instance();
        $this->outbox = $outbox;
        if ($this->outbox && \method_exists($this->outbox, 'setIngressAdapter')) {
            try {
                $this->outbox->setIngressAdapter($this->getIngressAdapter());
            } catch (\Throwable) {
                // best-effort: outbox should never break CRUD construction
            }
        }
    }

    // --- CREATE -------------------------------------------------------

    /** @param array<string,mixed> $row */
    public function create(#[\SensitiveParameter] array $row): array
    {
        return Retry::run(function () use ($row) {
            $res   = parent::create($row);
            $id    = $res['id'] ?? null;
            $after = $id !== null ? $this->getById($id, 0) : null;
            $this->emit(CrudEvent::OP_CREATE, $id, before: null, after: $after);
            return $res;
        });
    }

    /** @param array<string,mixed> $row */
    public function createAndFetch(#[\SensitiveParameter] array $row, int|\DateInterval|null $ttl = null): ?array
    {
        return Retry::run(function () use ($row, $ttl) {
            $after = parent::createAndFetch($row, $ttl);
            if ($after === null) {
                return null;
            }
            $id    = $after[$this->pk()] ?? null;
            $this->emit(CrudEvent::OP_CREATE, $id, before: null, after: $after);
            return $after;
        });
    }

    // --- UPDATE -------------------------------------------------------

    /**
     * @param int|string|array $id
     * @param array<string,mixed> $row
     */
    public function update(int|string|array $id, #[\SensitiveParameter] array $row): OperationResult
    {
        return Retry::run(function () use ($id, $row) {
            $before = $this->getById($id, 0);
            $affected = parent::updateById($id, $row);
            if ($affected > 0) {
                $after = $this->getById($id, 0);
                $this->emit(CrudEvent::OP_UPDATE, $id, $before, $after);
                return $this->mutationOk($before, $after, $affected);
            }
            return $this->mutationNotFound();
        });
    }

    /**
     * @param int|string|array $id
     * @param array<string,mixed> $row
     */
    public function updateOptimistic(int|string|array $id, #[\SensitiveParameter] array $row, int $expectedVersion): OperationResult
    {
        return Retry::run(function () use ($id, $row, $expectedVersion) {
            $before = $this->getById($id, 0);
            try {
                $affected = parent::updateByIdOptimistic($id, $row, $expectedVersion);
            } catch (OptimisticLockException $e) {
                return OperationResult::conflict($e->getMessage());
            }
            if ($affected > 0) {
                $after = $this->getById($id, 0);
                $this->emit(CrudEvent::OP_UPDATE, $id, $before, $after);
                return $this->mutationOk($before, $after, $affected);
            }
            return $this->mutationNotFound();
        });
    }

    /**
     * @param int|string|array $id
     */
    public function touch(int|string|array $id): OperationResult
    {
        return Retry::run(function () use ($id) {
            $before = $this->getById($id, 0);
            $affected = parent::touchById($id);
            if ($affected > 0) {
                $after = $this->getById($id, 0);
                $this->emit(CrudEvent::OP_TOUCH, $id, $before, $after);
                return $this->mutationOk($before, $after, $affected);
            }
            return $this->mutationNotFound();
        });
    }

    // --- DELETE / RESTORE --------------------------------------------

    /**
     * @param int|string|array $id
     */
    public function delete(int|string|array $id): OperationResult
    {
        return Retry::run(function () use ($id) {
            $before = $this->getById($id, 0);
            $affected = parent::deleteById($id);
            if ($affected > 0) {
                $this->emit(CrudEvent::OP_DELETE, $id, $before, null);
                return $this->mutationOk($before, null, $affected);
            }
            return $this->mutationNotFound();
        });
    }

    /**
     * @param int|string|array $id
     */
    public function restore(int|string|array $id): OperationResult
    {
        return Retry::run(function () use ($id) {
            $affected = parent::restoreById($id);
            if ($affected > 0) {
                $after = $this->getById($id, 0);
                $this->emit(CrudEvent::OP_RESTORE, $id, null, $after);
                return $this->mutationOk(null, $after, $affected);
            }
            return $this->mutationNotFound();
        });
    }

    // --- BULK ---------------------------------------------------------

    /** @param list<array<string,mixed>> $rows */
    public function createMany(#[\SensitiveParameter] array $rows): OperationResult
    {
        return Retry::run(function () use ($rows) {
            if (!$rows) {
                return OperationResult::ok(['affected' => 0]);
            }
            parent::insertMany($rows);
            $this->emit(CrudEvent::OP_BULK, null, null, null, affected: \count($rows));
            return OperationResult::ok(['affected' => \count($rows)]);
        });
    }

    /** @param list<array<string,mixed>> $rows */
    public function upsertMany(#[\SensitiveParameter] array $rows): OperationResult
    {
        return Retry::run(function () use ($rows) {
            if (!$rows) {
                return OperationResult::ok(['affected' => 0]);
            }
            foreach ($rows as $row) {
                parent::upsert($row);
            }
            $this->emit(CrudEvent::OP_BULK, null, null, null, affected: \count($rows));
            return OperationResult::ok(['affected' => \count($rows)]);
        });
    }

    // --- helpers ------------------------------------------------------

    private function mutationOk(?array $before, ?array $after, int $affected): OperationResult
    {
        return OperationResult::ok([
            'before'   => $before,
            'after'    => $after,
            'affected' => $affected,
        ]);
    }

    private function mutationNotFound(string $message = 'Row not found'): OperationResult
    {
        return OperationResult::notFound($message);
    }

    private function cacheNamespace(): string
    {
        return 'table-' . $this->tableName();
    }

    private function pk(): string
    {
        if ($this->cachedPk !== null) {
            return $this->cachedPk;
        }
        // GenericCrudService typically reads from Definitions::pk(); try to find it carefully.
        try {
            $ref = new \ReflectionClass($this);
            $ns  = $ref->getNamespaceName();
            $def = $ns ? ($ns . '\\Definitions') : 'Definitions';
            if (\class_exists($def) && \method_exists($def, 'pk')) {
                return $this->cachedPk = (string)$def::pk();
            }
        } catch (\Throwable) {
            // ignore
        }
        return $this->cachedPk = 'id';
    }

    private function tableName(): string
    {
        if ($this->cachedTable !== null) {
            return $this->cachedTable;
        }
        try {
            $ref = new \ReflectionClass($this);
            $ns  = $ref->getNamespaceName();
            $def = $ns ? ($ns . '\\Definitions') : 'Definitions';
            if (\class_exists($def) && \method_exists($def, 'table')) {
                return $this->cachedTable = (string)$def::table();
            }
        } catch (\Throwable) {
            // ignore
        }
        return $this->cachedTable = 'unknown';
    }

    /**
     * Emit an event and perform a best-effort outbox mirror.
     *
     * @param int|string|array|null $id
     * @param array<string,mixed>|null $before
     * @param array<string,mixed>|null $after
     */
    private function emit(string $op, int|string|array|null $id, ?array $before, ?array $after, int $affected = 1): void
    {
        // Normalize the operation for CrudEvent (keep 'bulk' as well)
        $allowed = [
            CrudEvent::OP_CREATE,
            CrudEvent::OP_UPDATE,
            CrudEvent::OP_DELETE,
            CrudEvent::OP_RESTORE,
            CrudEvent::OP_TOUCH,
            CrudEvent::OP_UPSERT,
            CrudEvent::OP_BULK,
        ];
        if (!\in_array($op, $allowed, true)) {
            $op = CrudEvent::OP_TOUCH;
        }

        $table = $this->tableName();

        $cryptoMeta = $this->buildCryptoMeta($table, $op, $before, $after);
        $context = [
            'cache_ns'     => 'table-' . $table,
            'version_col'  => $this->versionColumn(),
            'corr'         => $this->readServerHeader('X-Correlation-ID') ?? null,
        ];
        if ($cryptoMeta) {
            $context['crypto'] = $cryptoMeta;
        }

        $event = new CrudEvent(
            operation: $op,
            table:     $table,
            id:        $id,
            affected:  $affected,
            before:    $before,
            after:     $after,
            context:   $context
        );

        // 1) Best-effort dispatch (dispatcher is expected not to throw)
        // TODO(crypto-integrations): Attach manifest coverage hashes/context IDs to $event
        // so downstream consumers can verify the mutation passed through the crypto adapter.
        if ($this->dispatcher) {
            $this->dispatcher->dispatch($event);
        }

        // 2) Optional outbox mirror (best-effort; must not block the write path)
        if ($this->outbox) {
            try {
                $routing = $this->makeRoutingKey($op, $table);
                $tenant  = $this->extractTenant($before, $after);
                $traceId = $this->readServerHeader('X-TRACE-ID');

                // TODO(crypto-integrations): Replace direct OutboxRecord usage with the shared
                // DatabaseIngressAdapter helper so payload encryption + attestations happen here.
                $this->outbox->insert(
                    OutboxRecord::fromCrudEvent($event, routingKey: $routing, tenant: $tenant, traceId: $traceId),
                    delaySeconds: 0
                );
            } catch (\Throwable $e) {
                Telemetry::warn('Outbox insert failed', [
                    'op'    => $op,
                    'table' => $table,
                    'err'   => \substr($e->getMessage(), 0, 500),
                ]);
            }
        }
    }

    private function versionColumn(): ?string
    {
        try {
            $ref = new \ReflectionClass($this);
            $ns  = $ref->getNamespaceName();
            $def = $ns ? ($ns . '\\Definitions') : 'Definitions';
            if (\class_exists($def) && \method_exists($def, 'versionColumn')) {
                /** @var ?string */
                return $def::versionColumn();
            }
        } catch (\Throwable) {
            // ignore
        }
        return null;
    }

    private function makeRoutingKey(string $op, string $table): string
    {
        $t = $table !== '' ? $table : 'unknown';
        return 'crud.' . $t . '.' . $op;
    }

    /** @param array<string,mixed>|null $before @param array<string,mixed>|null $after */
    private function extractTenant(?array $before, ?array $after): ?string
    {
        $candidates = [
            $after['tenant_id']   ?? null,
            $before['tenant_id']  ?? null,
            $after['tenant']      ?? null,
            $before['tenant']     ?? null,
            $after['tenantId']    ?? null,
            $before['tenantId']   ?? null,
        ];
        foreach ($candidates as $v) {
            if ($v !== null && $v !== '') return (string)$v;
        }
        return null;
    }

    private function buildCryptoMeta(string $table, string $op, ?array $before, ?array $after): ?array
    {
        $columns = [];
        if ($after) {
            $columns = array_keys($after);
        } elseif ($before) {
            $columns = array_keys($before);
        }
        return \BlackCat\Database\Crypto\CryptoManifestMetadata::build($table, $op, $columns);
    }

    private function readServerHeader(string $name): ?string
    {
        // Safe, non-critical read from $_SERVER (e.g., reverse proxies add headers)
        $key = $name;
        if (isset($_SERVER[$key]) && \is_string($_SERVER[$key]) && $_SERVER[$key] !== '') {
            return $_SERVER[$key];
        }
        $httpKey = 'HTTP_' . \strtoupper(\str_replace('-', '_', $name));
        if (isset($_SERVER[$httpKey]) && \is_string($_SERVER[$httpKey]) && $_SERVER[$httpKey] !== '') {
            return $_SERVER[$httpKey];
        }
        return null;
    }
}
