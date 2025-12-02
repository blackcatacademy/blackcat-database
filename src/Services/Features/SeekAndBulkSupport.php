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

namespace BlackCat\Database\Services\Features;

use BlackCat\Database\Contracts\SeekPaginableRepository;
use BlackCat\Database\Contracts\BulkUpsertRepository;

/**
 * Drop-in trait for GenericCrudService (or other services) to leverage optional
 * repository capabilities without hard dependencies or BC breaks.
 *
 * Host class must provide:
 *   - protected object $repo;                     // the repository instance
 *   - public function paginate(object $criteria): array; // classical offset paging
 *
 * Optional (enables tryWithRowLock sugar):
 *   - public function withRowLock(mixed $id, callable $fn, string $mode = 'wait'): mixed;
 *   - public function txn(callable $fn): mixed;   // if available, bulk fallback runs in one TX
 *
 * @property object $repo
 */
trait SeekAndBulkSupport
{
    /**
     * @param object $criteria
     * @param array{col?:string|array,dir?:'asc'|'desc'|string,pk?:string|array} $order
     * @param array{colValue:mixed,pkValue:mixed}|null $cursor
     * @return array{0:array<int,array<string,mixed>>,1:array{colValue:mixed,pkValue:mixed}|null}
     */
    public function paginateBySeek(object $criteria, array $order, ?array $cursor, int $limit): array
    {
        $orderPk = $order['pk'] ?? '';
        if (\is_array($orderPk)) {
            $orderPk = (string)($orderPk[0] ?? '');
        }
        $col = '';
        if (\array_key_exists('col', $order)) {
            $colVal = $order['col'];
            if (\is_array($colVal)) {
                $colVal = $colVal[0] ?? '';
            }
            $col = (string)$colVal;
        }
        $dir = \strtolower((string)($order['dir'] ?? ''));

        // sane defaults
        $col = $col !== '' ? $col : ($orderPk ?: 'id');
        $dir = \in_array($dir, ['asc','desc'], true) ? $dir : 'desc';
        $pk  = $orderPk !== '' ? $orderPk : $col;

        $orderSpec = [
            'col' => $col,
            'dir' => $dir,
            'pk'  => $pk,
        ];

        if ($this->repo instanceof SeekPaginableRepository) {
            return $this->repo->paginateBySeek($criteria, $orderSpec, $cursor, max(1, (int)$limit));
        }

        // Fallback: emulate "page 1" via classic paginate(); trim to $limit
        $page  = $this->paginate($criteria);
        /** @var array<int,array<string,mixed>> $items */
        $items = $page['items'] ?? [];
        $items = $limit > 0 ? \array_slice($items, 0, (int)$limit) : $items;

        return [$items, null];
    }

    /**
     * Bulk upsert helper with graceful fallback to row-by-row upsert/insert.
     * If the host exposes txn(), the row-by-row fallback runs in one transaction.
     *
     * @param array<int,array<string,mixed>> $rows
     */
    public function bulkUpsert(array $rows): void
    {
        if (!$rows) {
            return;
        }

        if ($this->repo instanceof BulkUpsertRepository) {
            $this->repo->upsertMany($rows, [], []);
            return;
        }

        $runner = function() use ($rows): void {
            foreach ($rows as $r) {
                // Prefer repo->upsert(); fall back to insert(), save(), create()
                if (\is_object($this->repo) && \method_exists($this->repo, 'upsert')) {
                    $this->repo->upsert((array)$r);
                } elseif (\is_object($this->repo) && \method_exists($this->repo, 'insert')) {
                    $this->repo->insert((array)$r);
                } elseif (\is_object($this->repo) && \method_exists($this->repo, 'save')) {
                    $this->repo->save((array)$r);
                } elseif (\is_object($this->repo) && \method_exists($this->repo, 'create')) {
                    $this->repo->create((array)$r);
                } else {
                    // No known method; fail loud rather than silently dropping writes
                    throw new \LogicException('Repository lacks bulk and row-level upsert/insert methods.');
                }
            }
        };

        // If the host has txn(), keep the fallback atomic; otherwise run as-is.
        if (\method_exists($this, 'txn')) {
            /** @var callable $runner */
            $this->txn(static fn() => $runner());
        } else {
            $runner();
        }
    }

    /**
     * Friendly wrapper for SKIP LOCKED; returns null when row is currently locked.
     * Only active if the host class exposes withRowLock().
     *
     * @param callable $fn signature expected by withRowLock: fn($rowOrNull, $dbOrNull): mixed
     */
    public function tryWithRowLock(mixed $id, callable $fn): mixed
    {
        if (\method_exists($this, 'withRowLock')) {
            try {
                /** @var callable $fn */
                return $this->withRowLock($id, $fn, 'skip_locked');
            } catch (\PDOException | \RuntimeException $e) {
                $msg = \strtolower((string)$e->getMessage());
                if (\str_contains($msg, 'lock') || \str_contains($msg, 'skip locked')) {
                    return null; // behave as if row was locked
                }
                throw $e;
            }
        }

        // No-op fallback: invoke the closure without explicit locking, keeping the expected arity
        // No DB accessor available; run without connection context
        return $fn(null, null);
    }
}
