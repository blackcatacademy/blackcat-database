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

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;
use BlackCat\Database\Support\Telemetry;

/**
 * AdvisoryLock – portable advisory locks for MySQL/PostgreSQL.
 *
 * Semantics:
 * - MySQL:     GET_LOCK(name, timeout) / RELEASE_LOCK(name)
 * - PostgreSQL: pg_try_advisory_lock(int,int) with active polling until timeout,
 *               released via pg_advisory_unlock(int,int).
 *
 * Safety & DX:
 * - Fully parameterized (no value interpolation).
 * - Unified timeout handling (seconds; 0 = single attempt, >0 = wait).
 * - `withLock()` always attempts to release in `finally`; release failures are logged
 *   but not propagated (best-effort release).
 */
final class AdvisoryLock
{
    /**
     * Executes $work inside a critical section protected by an advisory lock.
     *
     * @template T
     * @param non-empty-string $name
     * @param positive-int|0 $timeoutSec
     * @param callable():T $work
     * @return T
     */
    public static function withLock(Database $db, #[\SensitiveParameter] string $name, int $timeoutSec, callable $work): mixed
    {
        self::acquire($db, $name, $timeoutSec);
        try {
            return $work();
        } finally {
            try {
                self::release($db, $name);
            } catch (\Throwable $e) {
                // Best-effort: lock release must not break the critical path
                Telemetry::warn('AdvisoryLock release failed', ['name' => $name, 'err' => \substr($e->getMessage(), 0, 300)]);
            }
        }
    }

    /**
     * Acquires a lock with the given timeout. Throws when the timeout expires.
     *
     * @param non-empty-string $name
     * @param positive-int|0 $timeoutSec
     */
    public static function acquire(Database $db, #[\SensitiveParameter] string $name, int $timeoutSec): void
    {
        $name = \trim($name);
        if ($name === '') {
            throw new \InvalidArgumentException('AdvisoryLock: name must be a non-empty string');
        }
        $timeoutSec = \max(0, $timeoutSec);

        if ($db->dialect()->isMysql()) {
            // MySQL – GET_LOCK returns 1=ok, 0=timeout, NULL=error
            /** @var int|string|null $val */
            $val = $db->fetchValue('SELECT GET_LOCK(:n, :t)', [':n' => $name, ':t' => $timeoutSec], null);
            if ($val === 1 || $val === '1') {
                return;
            }
            if ($val === 0 || $val === '0') {
                throw new \RuntimeException("AdvisoryLock: timeout acquiring '{$name}'");
            }
            throw new \RuntimeException("AdvisoryLock: GET_LOCK failed for '{$name}'");
        }

        // PostgreSQL – emulate timeout via repeated pg_try_advisory_lock
        [$k1, $k2] = self::hashKeyToInt32Pair($name);
        $deadlineMs = self::nowMs() + ($timeoutSec * 1000);

        do {
            /** @var int|bool|string|null $ok */
            $ok = $db->fetchValue('SELECT pg_try_advisory_lock(:k1, :k2)', [':k1' => $k1, ':k2' => $k2], null);
            if ($ok === true || $ok === 1 || $ok === 't' || $ok === '1') {
                return; // acquired
            }
            if ($timeoutSec === 0) {
                break; // single attempt only
            }
            \usleep(50_000); // 50 ms
        } while (self::nowMs() < $deadlineMs);

        throw new \RuntimeException("AdvisoryLock: timeout acquiring '{$name}'");
    }

    /**
     * Releases a previously acquired lock. Silently ignores missing/non-owned locks.
     *
     * @param non-empty-string $name
     */
    public static function release(Database $db, #[\SensitiveParameter] string $name): void
    {
        if ($db->dialect()->isMysql()) {
            // RELEASE_LOCK returns 1=OK, 0=missing/not owner, NULL=error – ignore result
            $db->fetchValue('SELECT RELEASE_LOCK(:n)', [':n' => $name], null);
            return;
        }

        [$k1, $k2] = self::hashKeyToInt32Pair($name);
        $db->fetchValue('SELECT pg_advisory_unlock(:k1, :k2)', [':k1' => $k1, ':k2' => $k2], null);
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /** Returns a pair of signed 32-bit ints suitable for pg_*_advisory_lock(int,int). */
    private static function hashKeyToInt32Pair(string $name): array
    {
        // Stable hash with low collision risk → first 8 bytes of SHA-1
        $h = \hash('sha1', $name, true);
        /** @var array{1:int,2:int} $u */
        $u = \unpack('N2', \substr($h, 0, 8)); // 2× big-endian uint32

        $k1 = self::toSigned32($u[1]);
        $k2 = self::toSigned32($u[2]);
        return [$k1, $k2];
    }

    /** Converts an unsigned 32-bit value (0..2^32-1) to signed int32 (-2^31..2^31-1). */
    private static function toSigned32(int $x): int
    {
        if ($x >= 0x80000000) {
            $x -= 0x100000000;
        }
        return $x;
    }

    /** Monotonic time in ms. */
    private static function nowMs(): int
    {
        return (int) (\hrtime(true) / 1_000_000);
    }
}
