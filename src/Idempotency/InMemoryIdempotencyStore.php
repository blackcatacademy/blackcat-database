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

namespace BlackCat\Database\Idempotency;

/**
 * InMemoryIdempotencyStore
 *
 * Simple, fast, and intentionally thread-unsafe in-memory idempotency store;
 * best suited for tests, CLI utilities, and local development.
 *
 * Features:
 * - Atomic `begin()` at the process level (map-based key check).
 * - Optional TTL for `in_progress` records (auto-expire).
 * - Consolidated output from `get()` (status, result, reason, startedAt, completedAt).
 *
 * Notes:
 * - PHP-FPM/worker mode does not share memory across processes, so this implementation
 *   targets single-process scenarios only (tests, local runs).
 *
 * @phpstan-type Record array{
 *   status: 'in_progress'|'success'|'failed',
 *   result?: array<string,mixed>|null,
 *   reason?: non-empty-string|null,
 *   startedAt?: int,
 *   completedAt?: int
 * }
 */
final class InMemoryIdempotencyStore implements IdempotencyStore
{
    /**
     * @var array<string,array{
     *   status: 'in_progress'|'success'|'failed',
     *   result?: array<string,mixed>|null,
     *   reason?: non-empty-string|null,
     *   startedAt?: int,
     *   completedAt?: int,
     *   expiresAt?: int
     * }>
     */
    private array $data = [];

    /** {@inheritDoc} */
    public function get(#[\SensitiveParameter] string $key): ?array
    {
        $this->gcExpiredKey($key);
        if (!isset($this->data[$key])) {
            return null;
        }
        return $this->publicView($this->data[$key]);
    }

    /**
     * {@inheritDoc}
     *
     * @param positive-int $ttlSeconds
     */
    public function begin(#[\SensitiveParameter] string $key, int $ttlSeconds = 3600): bool
    {
        $this->gcExpiredKey($key);
        if (isset($this->data[$key])) {
            return false; // already present (IN_PROGRESS / SUCCESS / FAILED)
        }
        $ttl = max(1, $ttlSeconds);

        $this->data[$key] = [
            'status'    => self::STATUS_IN_PROGRESS,
            'result'    => null,
            'startedAt' => $this->now(),
            'expiresAt' => $this->now() + $ttl,
        ];
        return true;
    }

    /** {@inheritDoc} */
    public function commit(#[\SensitiveParameter] string $key, #[\SensitiveParameter] array $result): void
    {
        // If commit() is called without begin(), create a record (useful for idempotency wrappers).
        $rec = $this->data[$key] ?? [
            'status'    => self::STATUS_IN_PROGRESS,
            'result'    => null,
            'startedAt' => $this->now(),
        ];

        $rec['status']      = self::STATUS_SUCCESS;
        $rec['result']      = $result;
        $rec['completedAt'] = $this->now();
        unset($rec['expiresAt']);

        $this->data[$key] = $rec;
    }

    /** {@inheritDoc} */
    public function fail(#[\SensitiveParameter] string $key, #[\SensitiveParameter] string $reason): void
    {
        $reason = trim($reason);
        if ($reason == '') {
            $reason = 'unknown';
        }

        $rec = $this->data[$key] ?? [
            'status'    => self::STATUS_IN_PROGRESS,
            'result'    => null,
            'startedAt' => $this->now(),
        ];

        $rec['status']      = self::STATUS_FAILED;
        $rec['result']      = null;
        $rec['reason']      = $reason;
        $rec['completedAt'] = $this->now();
        unset($rec['expiresAt']);

        $this->data[$key] = $rec;
    }

    // ---------------- Internal helpers ----------------

    /** @return Record */
    private function publicView(array $rec): array
    {
        // Do not expose internal expiresAt
        $out = $rec;
        unset($out['expiresAt']);
        return $out;
    }

    private function gcExpiredKey(string $key): void
    {
        $rec = $this->data[$key] ?? null;
        if ($rec === null) {
            return;
        }
        if (($rec['status'] ?? null) === self::STATUS_IN_PROGRESS) {
            $exp = $rec['expiresAt'] ?? null;
            if (\is_int($exp) && $exp <= $this->now()) {
                unset($this->data[$key]); // lock/attempt expired
            }
        }
    }

    private function now(): int
    {
        return \time();
    }
}
