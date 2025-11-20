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

use BlackCat\Database\Idempotency\IdempotencyStore;
use BlackCat\Database\Support\Telemetry;

/**
 * IdempotentCrudService
 *
 * Extends {@see EventfulCrudService} with an idempotent wrapper:
 * - `withIdempotency($key, $fn)` runs the action exactly once per key.
 * - "*Idempotent" convenience wrappers for common CRUD operations.
 *
 * Safety & DX:
 * - Consistent status values: 'in_progress' | 'success' | 'failed'
 *   (also maps historical 'done' -> 'success').
 * - Best-effort storage: store failures do **not block** the main action (we log and continue).
 * - Optional waiting for the result if someone else is performing the operation (default 2s).
 * - Results are stored as arrays. Scalars are wrapped as `['value' => $res]` and unwrapped when reading.
 */
class IdempotentCrudService extends EventfulCrudService
{
    public function __construct(
        \BlackCat\Core\Database $db,
        \BlackCat\Database\Contracts\ContractRepository $repo,
        ?\BlackCat\Core\Database\QueryCache $qcache = null,
        ?\BlackCat\Database\Events\CrudEventDispatcher $dispatcher = null,
        ?\BlackCat\Database\Outbox\OutboxRepository $outbox = null,
        private ?IdempotencyStore $idem = null,
        private int $defaultTtlSec = 3600,
        private int $defaultWaitMs = 2000
    ) {
        parent::__construct($db, $repo, $qcache, $dispatcher, $outbox);
    }

    /** Stable, short, and "clean" idempotency key (prefix + db + sanitization + hash when too long). */
    private function buildIdemKey(string $scope, string $raw): string
    {
        $dbId = 'db';
        try { $dbId = (string)$this->db()->id(); } catch (\Throwable) {}
        $base = $scope . ':' . $dbId . ':' . (string)\preg_replace('~[^A-Za-z0-9_.:-]+~', '.', \trim($raw));
        if (\strlen($base) > 120) {
            $base = \substr($base, 0, 90) . '|' . \substr(\hash('sha256', $base), 0, 16);
        }
        return $base;
    }

    /**
     * Run the action at most once for the given key. If a result already exists, return it.
     *
     * @template T
     * @param non-empty-string $key
     * @param callable():T     $fn
     * @param positive-int     $ttlSeconds  how long to keep the result (hint for the store)
     * @param int              $waitForMs   how many ms to wait if the operation is running elsewhere
     * @return T
     */
    public function withIdempotency(
        #[\SensitiveParameter] string $key,
        callable $fn,
        ?int $ttlSeconds = null,
        ?int $waitForMs = null
    ): mixed {
        $key = \trim($key);
        if ($key === '') {
            throw new \InvalidArgumentException('Idempotency key must be a non-empty string.');
        }
        $ttlSeconds ??= $this->defaultTtlSec;
        $waitForMs  ??= $this->defaultWaitMs;

        // Without a store -> just run through
        if ($this->idem === null) {
            return $fn();
        }

        // 1) Try a fast hit
        try {
            $seen = $this->idem->get($key);
        } catch (\Throwable $e) {
            Telemetry::warn('IdempotencyStore::get failed (passthrough)', ['err' => $e->getMessage()]);
            return $fn(); // best-effort
        }

        $status = $this->normalizeStatus($seen['status'] ?? null);
        if ($status === IdempotencyStore::STATUS_SUCCESS) {
            return $this->unwrapResult($seen['result'] ?? null);
        }
        if ($status === IdempotencyStore::STATUS_FAILED) {
            $reason = $this->extractReason($seen);
            throw new \RuntimeException('Idempotent operation has failed previously: ' . $reason);
        }

        // 2) Attempt to start – only if it has not begun yet
        $begun = false;
        try {
            $begun = $this->idem->begin($key, $ttlSeconds);
        } catch (\Throwable $e) {
            Telemetry::warn('IdempotencyStore::begin failed (passthrough)', ['err' => $e->getMessage()]);
            return $fn(); // best-effort
        }

        if (!$begun) {
            // Someone else is running – briefly wait for the result
            $deadline = (int)(\hrtime(true) / 1_000_000) + \max(0, $waitForMs);
            do {
                try {
                    $seen = $this->idem->get($key);
                } catch (\Throwable $e) {
                    Telemetry::warn('IdempotencyStore::get (wait) failed', ['err' => $e->getMessage()]);
                    break; // leave the wait loop
                }
                $status = $this->normalizeStatus($seen['status'] ?? null);
                if ($status === IdempotencyStore::STATUS_SUCCESS) {
                    return $this->unwrapResult($seen['result'] ?? null);
                }
                if ($status === IdempotencyStore::STATUS_FAILED) {
                    $reason = $this->extractReason($seen);
                    throw new \RuntimeException('Idempotent operation has failed previously: ' . $reason);
                }
                \usleep(50_000); // 50ms
            } while ((int)(\hrtime(true) / 1_000_000) < $deadline);

            // After the timeout prefer fail-fast (do not execute again)
            throw new \RuntimeException('Idempotent operation is still in progress for key: ' . $key);
        }

        // 3) We are the "owner" – run the action and store the result
        try {
            $res = $fn();
            $payload = \is_array($res) ? $res : ['value' => $res];

            try {
                $this->idem->commit($key, $payload);
            } catch (\Throwable $e) {
                Telemetry::warn('IdempotencyStore::commit failed (ignored)', ['err' => $e->getMessage()]);
            }
            return $res;
        } catch (\Throwable $e) {
            try {
                $this->idem->fail($key, \substr($e->getMessage(), 0, 500));
            } catch (\Throwable $e2) {
                Telemetry::warn('IdempotencyStore::fail failed (ignored)', ['err' => $e2->getMessage()]);
            }
            throw $e;
        }
    }

    // ---------------- Convenience wrappers ----------------

    /** @param array<string,mixed> $row */
    public function createIdempotent(#[\SensitiveParameter] array $row, #[\SensitiveParameter] string $key, ?int $ttlSec = null): array
    {
        return $this->withIdempotency($this->buildIdemKey('create', $key), fn() => $this->create($row), $ttlSec);
    }

    /**
     * @param int|string|array $id
     * @param array<string,mixed> $row
     */
    public function updateIdempotent(int|string|array $id, #[\SensitiveParameter] array $row, #[\SensitiveParameter] string $key, ?int $ttlSec = null): \BlackCat\Database\Support\OperationResult
    {
        return $this->withIdempotency($this->buildIdemKey('update', $key), fn() => $this->update($id, $row), $ttlSec);
    }

    /** @param array<string,mixed> $row */
    public function createAndFetchIdempotent(#[\SensitiveParameter] array $row, #[\SensitiveParameter] string $key, ?int $ttlSec = null): ?array
    {
        return $this->withIdempotency($this->buildIdemKey('create_fetch', $key), fn() => $this->createAndFetch($row, 0), $ttlSec);
    }

    /** @param array<string,mixed> $row */
    public function upsertIdempotent(#[\SensitiveParameter] array $row, #[\SensitiveParameter] string $key, ?int $ttlSec = null): void
    {
        $this->withIdempotency($this->buildIdemKey('upsert', $key), function () use ($row) {
            $this->upsert($row);
            return ['ok' => true];
        }, $ttlSec);
    }

    /**
     * @param int|string|array $id
     */
    public function deleteIdempotent(int|string|array $id, #[\SensitiveParameter] string $key, ?int $ttlSec = null): \BlackCat\Database\Support\OperationResult
    {
        return $this->withIdempotency($this->buildIdemKey('delete', $key), fn() => $this->delete($id), $ttlSec);
    }

    /**
     * @param int|string|array $id
     */
    public function restoreIdempotent(int|string|array $id, #[\SensitiveParameter] string $key, ?int $ttlSec = null): \BlackCat\Database\Support\OperationResult
    {
        return $this->withIdempotency($this->buildIdemKey('restore', $key), fn() => $this->restore($id), $ttlSec);
    }

    /**
     * @param int|string|array $id
     */
    public function touchIdempotent(int|string|array $id, #[\SensitiveParameter] string $key, ?int $ttlSec = null): \BlackCat\Database\Support\OperationResult
    {
        return $this->withIdempotency($this->buildIdemKey('touch', $key), fn() => $this->touch($id), $ttlSec);
    }

    // ---------------- Internals ----------------

    /** @return 'in_progress'|'success'|'failed'|null */
    private function normalizeStatus(?string $s): ?string
    {
        if ($s === null) return null;
        $s = \strtolower(\trim($s));
        if ($s === 'done') return IdempotencyStore::STATUS_SUCCESS; // backward compatibility
        return \in_array($s, [
            IdempotencyStore::STATUS_IN_PROGRESS,
            IdempotencyStore::STATUS_SUCCESS,
            IdempotencyStore::STATUS_FAILED
        ], true) ? $s : null;
    }

    /** Unwrap a stored result (see the scalar wrapper). */
    private function unwrapResult(mixed $stored): mixed
    {
        if (\is_array($stored) && \array_key_exists('value', $stored) && \count($stored) === 1) {
            return $stored['value'];
        }
        return $stored;
    }

    /** Extract the "reason" whether it sits in top-level `reason` or `result['error']`. */
    private function extractReason(?array $record): string
    {
        $reason = '';
        if (\is_array($record)) {
            $reason = (string)($record['reason'] ?? '');
            if ($reason === '' && \is_array($record['result'] ?? null)) {
                $reason = (string)($record['result']['error'] ?? '');
            }
        }
        return $reason !== '' ? $reason : 'unknown';
    }
}
