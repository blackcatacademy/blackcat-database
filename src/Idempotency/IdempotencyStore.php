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
 * IdempotencyStore – contract for persisting idempotent operation state.
 *
 * Semantics:
 * - `begin($key)` MUST be an atomic create-if-absent. Returns false if the key already exists
 *   (regardless of status), so callers can decide whether to fetch the outcome instead.
 * - `commit($key, $result)` saves the final result and marks the record as SUCCESS.
 * - `fail($key, $reason)` sets state to FAILED with a reason (usable for observability/retry logic).
 * - `get($key)` returns the latest known state (including result/reason) or null when the record does not exist/expired.
 *
 * Implementation tips:
 * - Consider TTL/expiration (DB/Redis-level) to automatically purge stale keys.
 * - Return a consistent structure and keep it small (serialize only what is necessary).
 * - Protect sensitive data (user IDs, payloads) by marking parameters with #[\SensitiveParameter].
 *
 * @phpstan-type Status 'in_progress'|'success'|'failed'
 * @phpstan-type Result array<string,mixed>
 * @phpstan-type Record array{
 *   status: Status,
 *   result?: Result|null,
 *   reason?: non-empty-string|null,
 *   startedAt?: int,        // unix time (s)
 *   completedAt?: int       // unix time (s)
 * }
 *
 * @psalm-type Status = 'in_progress'|'success'|'failed'
 * @psalm-type Result = array<string,mixed>
 * @psalm-type Record = array{
 *   status: Status,
 *   result?: Result|null,
 *   reason?: non-empty-string|null,
 *   startedAt?: int,
 *   completedAt?: int
 * }
 */
interface IdempotencyStore
{
    public const STATUS_IN_PROGRESS = 'in_progress';
    public const STATUS_SUCCESS     = 'success';
    public const STATUS_FAILED      = 'failed';

    /**
     * Fetches the state of an idempotent operation.
     *
     * @param non-empty-string $key
     * @return Record|null
     */
    public function get(#[\SensitiveParameter] string $key): ?array;

    /**
     * Starts an idempotent operation – atomically creates a record if it does not exist.
     *
     * @param non-empty-string $key
     * @param positive-int $ttlSeconds optional TTL recommendation (implementation may ignore)
     * @return bool false if the record already exists (IN_PROGRESS/SUCCESS/FAILED), true otherwise
     */
    public function begin(#[\SensitiveParameter] string $key, int $ttlSeconds = 3600): bool;

    /**
     * Commits the result of the idempotent operation.
     *
     * @param non-empty-string $key
     * @param Result $result
     */
    public function commit(#[\SensitiveParameter] string $key, #[\SensitiveParameter] array $result): void;

    /**
     * Marks the operation as failed with a reason (for observability/diagnostics).
     *
     * @param non-empty-string $key
     * @param non-empty-string $reason
     */
    public function fail(#[\SensitiveParameter] string $key, #[\SensitiveParameter] string $reason): void;
}
