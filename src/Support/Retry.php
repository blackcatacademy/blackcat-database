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

/**
 * Resilient retry helper for transient DB issues (deadlock/serialization/lock/timeout/connection).
 *
 * Highlights:
 * - Exponential backoff with jitter (full/equal/decorrelated), upper bound, and optional deadline.
 * - Detects transient errors via SQLSTATE, vendor codes (MySQL/MariaDB/PostgreSQL), and error text.
 * - onRetry() hook for logging/telemetry, custom classifier, and pluggable sleep().
 * - Backwards compatible: {@see Retry::run()} keeps the legacy signature.
 *
 * Examples:
 *  $value = Retry::run(fn() => $db->exec($sql));
 *
 *  $value = Retry::runAdvanced(
 *      fn() => $repo->update(...),
 *      attempts: 5,
 *      initialMs: 30,
 *      factor: 2.0,
 *      maxMs: 1000,
 *      jitter: 'full',           // 'none'|'equal'|'full'|'decorrelated'
 *      deadlineMs: 5000,
 *      onRetry: function (int $attempt, \Throwable $e, int $sleepMs, array $ctx): void {
 *          // log/metrics…
 *      }
 *  );
 */
final class Retry
{
    /** @var list<callable(\Throwable):array{transient:bool,reason?:string}> */
    private static array $customClassifiers = [];
    /**
     * Original simple API – exponential backoff + full jitter.
     *
     * @template T
     * @param callable():T $fn
     * @return T
     */
    public static function run(callable $fn, int $maxAttempts = 3, int $initialSleepMs = 25, float $factor = 2.0): mixed
    {
        return self::runAdvanced(
            $fn,
            attempts: $maxAttempts,
            initialMs: $initialSleepMs,
            factor: $factor,
            maxMs: 1000,
            jitter: 'full'
        );
    }

    /**
     * Register a custom classifier used before built-in heuristics.
     *
     * @param callable(\Throwable):array{transient:bool,reason?:string} $classifier
     */
    public static function registerClassifier(callable $classifier): void
    {
        self::$customClassifiers[] = $classifier;
    }

    /**
     * Advanced API with optional parameters.
     *
     * @template T
     * @param callable():T                            $fn
     * @param int                                     $attempts      total attempts (>=1)
     * @param int                                     $initialMs     initial delay (ms)
     * @param float                                   $factor        backoff multiplier (>1)
     * @param int|null                                $maxMs         max single sleep (ms)
     * @param 'none'|'equal'|'full'|'decorrelated'    $jitter        jitter strategy
     * @param int|null                                $deadlineMs    total time budget (ms) – best-effort
     * @param callable(int,\Throwable,int,array):void|null $onRetry  hook: ($attempt, $e, $sleepMs, $ctx)
     * @param callable(int):void|null                 $sleep         custom sleep(ms) (for tests)
     * @param callable(\Throwable):array{transient:bool,reason?:string}|null $classifier custom classifier
     * @return T
     */
    public static function runAdvanced(
        callable $fn,
        int $attempts = 3,
        int $initialMs = 25,
        float $factor = 2.0,
        ?int $maxMs = 1000,
        string $jitter = 'full',
        ?int $deadlineMs = null,
        ?callable $onRetry = null,
        ?callable $sleep = null,
        ?callable $classifier = null
    ): mixed {
        $attempts   = max(1, $attempts);
        $initialMs  = max(0, $initialMs);
        $factor     = ($factor > 1.0) ? $factor : 2.0;
        $maxMs      = ($maxMs !== null) ? max(1, $maxMs) : null;
        $deadlineAt = ($deadlineMs !== null) ? (int)round(microtime(true) * 1000) + max(1, $deadlineMs) : null;

        $sleep ??= static function (int $ms): void {
            // usleep bere mikrosekundy
            if ($ms <= 0) {
                return;
            }
            \usleep($ms * 1000);
        };

        $classifier ??= static function (\Throwable $e): array {
            return self::classify($e);
        };

        $delay = $initialMs;

        for ($attempt = 1; $attempt <= $attempts; $attempt++) {
            try {
                return $fn();
            } catch (\Throwable $e) {
                $info = $classifier($e);
                $isTransient = (bool)($info['transient'] ?? false);

                // If not transient or already on the last attempt, rethrow.
                if (!$isTransient || $attempt >= $attempts) {
                    throw $e;
                }

                // Deadline best-effort: if no time remains even for the smallest sleep, stop.
                if ($deadlineAt !== null) {
                    $now = (int)round(microtime(true) * 1000);
                    if ($now >= $deadlineAt) {
                        throw $e;
                    }
                }

                // Compute delay (exponential backoff)
                $base = ($attempt === 1) ? $delay : (int)max(1, $delay * $factor);
                $delay = $base;

                // Aplikace jitteru
                $sleepMs = self::applyJitter($delay, $jitter, $maxMs);

                // Adjust by deadline (shorten if it would overflow)
                if ($deadlineAt !== null) {
                    $now = (int)round(microtime(true) * 1000);
                    $budget = $deadlineAt - $now;
                    if ($budget <= 0) {
                        throw $e;
                    }
                    $sleepMs = min($sleepMs, $budget);
                }

                if ($onRetry) {
                    try {
                        $onRetry($attempt, $e, $sleepMs, [
                            'sqlstate' => self::sqlState($e),
                            'code'     => self::vendorCode($e),
                            'reason'   => $info['reason'] ?? null,
                        ]);
                    } catch (\Throwable) {
                        // never let hook break retry flow
                    }
                }

                $sleep($sleepMs);

                // Prepare the next delay (before the following iteration)
                $delay = $sleepMs;
                continue;
            }
        }

        // Should not happen: loop returns/throws inside
        throw new \RuntimeException('Retry failed without throwing original error.');
    }

    /* ============================ Error classification ============================ */

    /**
     * Classify errors via SQLSTATE, vendor codes, and message text.
     * Returns ['transient'=>bool, 'reason'=>string].
     */
    public static function classify(\Throwable $e): array
    {
        foreach (self::$customClassifiers as $custom) {
            try {
                $res = $custom($e);
                if (!\is_array($res)) {
                    continue;
                }
                if (!array_key_exists('transient', $res)) {
                    continue;
                }
                return [
                    'transient' => (bool)$res['transient'],
                    'reason' => $res['reason'] ?? null,
                ];
            } catch (\Throwable) {
                // ignore faulty custom classifier
            }
        }

        // 1) Prefer central detection if available (Single Source of Truth)
        $pdo = self::pdoFromChain($e);
        if ($pdo && \class_exists(\BlackCat\Core\Database::class) && \method_exists(\BlackCat\Core\Database::class, 'isTransientPdo')) {
            try {
                if (\BlackCat\Core\Database::isTransientPdo($pdo)) {
                    return ['transient' => true, 'reason' => 'core:isTransientPdo'];
                }
            } catch (\Throwable) {
                // best-effort: if the core check fails continue with heuristic below
            }
        }

        // 2) Heuristics using SQLSTATE/vendor codes/text (fallback)
        $sqlstate = self::sqlState($e);
        $vcode    = self::vendorCode($e);
        $msg      = strtolower(self::messageChain($e));

        // --- PostgreSQL SQLSTATE ---
        // 40001: serialization_failure
        // 40P01: deadlock_detected
        // 55P03: lock_not_available
        // 57014: query_canceled (e.g. statement timeout)
        // 53300: too_many_connections
        // 08000/08001/08003/08004/08006: connection errors
        // 57P01: admin_shutdown (often transient during restart)
        $pgTransient = [
            '40001','40P01','55P03','57014','53300','08000','08001','08003','08004','08006','57P01',
        ];
        if ($sqlstate !== null && in_array($sqlstate, $pgTransient, true)) {
            return ['transient' => true, 'reason' => "sqlstate:$sqlstate"];
        }

        // --- MySQL/MariaDB vendor codes ---
        // 1213: ER_LOCK_DEADLOCK
        // 1205: ER_LOCK_WAIT_TIMEOUT
        // 1040: ER_CON_COUNT_ERROR (too many connections)
        // 2006: CR_SERVER_GONE_ERROR
        // 2013: CR_SERVER_LOST
        // 1047: ER_UNKNOWN_COM_ERROR (e.g. restart)
        // 1042: ER_BAD_HOST_ERROR (network/DNS – often transient)
        $mysqlTransient = [1213, 1205, 1040, 2006, 2013, 1047, 1042];
        if ($vcode !== null && in_array($vcode, $mysqlTransient, true)) {
            return ['transient' => true, 'reason' => "mysql:$vcode"];
        }

        // --- Generic text indicators (best-effort) ---
        $needles = [
            'deadlock found',                 // MySQL
            'lock wait timeout',              // MySQL
            'too many connections',           // oba
            'could not serialize access',     // PG
            'could not obtain lock',          // PG
            'connection reset by peer',       // network
            'server has gone away',           // MySQL
            'lost connection to mysql server',
            'connection refused',
            'timeout expired',
            'canceling statement due to statement timeout',
        ];
        foreach ($needles as $n) {
            if (strpos($msg, $n) !== false) {
                return ['transient' => true, 'reason' => "msg:$n"];
            }
        }

        // Generic SQLSTATE for timeouts (ODBC): HYT00, S1T00; generic HY000
        if ($sqlstate !== null && in_array($sqlstate, ['HYT00','S1T00','HY000'], true)) {
            // HY000 is generic – treat as transient only if text mentions "timeout"
            if ($sqlstate !== 'HY000' || str_contains($msg, 'timeout')) {
                return ['transient' => true, 'reason' => "sqlstate:$sqlstate"];
            }
        }

        return ['transient' => false, 'reason' => 'non_transient'];
    }

    /** Backwards-compatible helper: true if the error looks transient. */
    public static function isTransient(\Throwable $e): bool
    {
        return (bool)(self::classify($e)['transient'] ?? false);
    }

    /** Build a combined message from the entire exception chain (e + previous). */
    private static function messageChain(\Throwable $e): string
    {
        $parts = [];
        for ($cur = $e; $cur !== null; $cur = $cur->getPrevious()) {
            $parts[] = (string)$cur->getMessage();
        }
        return implode(' | ', $parts);
    }

    /** Retrieve SQLSTATE (if available) from a PDOException in the chain. */
    public static function sqlState(\Throwable $e): ?string
    {
        for ($cur = $e; $cur !== null; $cur = $cur->getPrevious()) {
            if ($cur instanceof \PDOException) {
                $ei = $cur->errorInfo ?? null;
                if (is_array($ei) && isset($ei[0]) && is_string($ei[0]) && $ei[0] !== '') {
                    return strtoupper($ei[0]);
                }
            }
        }
        return null;
    }

    /** Retrieve vendor code (int) from a PDOException in the chain. */
    public static function vendorCode(\Throwable $e): ?int
    {
        for ($cur = $e; $cur !== null; $cur = $cur->getPrevious()) {
            if ($cur instanceof \PDOException) {
                $ei = $cur->errorInfo ?? null;
                if (is_array($ei) && isset($ei[1]) && is_numeric($ei[1])) {
                    return (int)$ei[1];
                }
                $c = $cur->getCode();
                if (is_numeric($c)) {
                    return (int)$c;
                }
            }
        }
        return null;
    }

    /************ internal helper: extract PDOException from cause chain ************/
    private static function pdoFromChain(\Throwable $e): ?\PDOException
    {
        for ($cur = $e; $cur !== null; $cur = $cur->getPrevious()) {
            if ($cur instanceof \PDOException) {
                return $cur;
            }
        }
        return null;
    }

    /* ============================ Backoff & Jitter ============================ */

    /**
     * Apply jitter to the delay and return the resulting sleep in ms (with ceiling).
     *
     * @param int         $delayMs   proposed delay before jitter
     * @param string      $jitter    'none'|'equal'|'full'|'decorrelated'
     * @param int|null    $maxMs     upper bound (ms)
     */
    private static function applyJitter(int $delayMs, string $jitter, ?int $maxMs): int
    {
        $delayMs = max(1, $delayMs);

        switch (strtolower($jitter)) {
            case 'none':
                $sleepMs = $delayMs;
                break;

            case 'equal':
                // Equal jitter: base/2 + rand(0, base/2)
                $half = (int)max(1, $delayMs / 2);
                $sleepMs = $half + self::randInt(0, $half);
                break;

            case 'decorrelated':
                // Decorrelated jitter (AWS backoff) – random between min and 3*prev, bounded
                $hi = min($delayMs * 3, $maxMs ?? PHP_INT_MAX);
                $sleepMs = self::randInt($delayMs, (int)$hi);
                break;

            case 'full':
            default:
                // „Full jitter“: rand(0, base)
                $sleepMs = self::randInt(0, $delayMs);
                break;
        }

        if ($maxMs !== null) {
            $sleepMs = min($sleepMs, $maxMs);
        }
        return max(1, (int)$sleepMs);
    }

    /** Safe replacement for random_int with fallback. */
    private static function randInt(int $min, int $max): int
    {
        if ($min >= $max) {
            return $min;
        }
        try {
            return \random_int($min, $max);
        } catch (\Throwable) {
            return $min + (int)floor((mt_rand() / mt_getrandmax()) * ($max - $min + 1));
        }
    }
}
