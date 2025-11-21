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
use BlackCat\Core\Database\QueryCache;
use Psr\Log\LoggerInterface;

/**
 * ServiceHelpers – convenient and safe helpers for service layers using Database.
 *
 * Expectations:
 *  - Class using the trait has properties:
 *      private Database $db;
 *      private ?QueryCache $qcache = null;
 *      private ?LoggerInterface $logger = null;
 *  - Optionally exposes getDb() / getQueryCache() / getLogger().
 *
 * Features:
 *  - Consistent transactional API (R/W and read-only) including retries with exponential backoff.
 *  - Scope-based helpers: advisory lock, statement timeout, isolation.
 *  - Integrated cache wrappers (rows / row / value) – bypass when dependency missing.
 *  - Keyset (seek) pagination via Database::paginateKeyset().
 *  - Safe logging of retry attempts (best-effort; never throws).
 */
trait ServiceHelpers
{
    /** Build a safe, short, stable key for advisory locks. */
    private function buildLockKey(string $name): string
    {
        // prefix + DB id → isolation across instances
        $dbId = 'db';
        try { $dbId = (string)$this->db()->id(); } catch (\Throwable) {}
        $base = 'svc:' . $dbId . ':' . (string)\preg_replace('~[^A-Za-z0-9_.:-]+~', '.', $name ?: 'lock');
        // MySQL GET_LOCK() limit is ~64 chars → shorten and add hash for stability
        if (\strlen($base) > 48) {
            $base = \substr($base, 0, 32) . '|' . \substr(\hash('sha256', $base), 0, 12);
        }
        return $base;
    }

    /** ---------- Dependency accessors ---------- */

    protected function db(): Database
    {
        // Prefer property ($this->db), fallback to getDb()
        if (\property_exists($this, 'db') && $this->db instanceof Database) {
            return $this->db;
        }
        if (\method_exists($this, 'getDb')) {
            $db = $this->getDb();
            if ($db instanceof Database) {
                return $db;
            }
        }
        throw new \LogicException('Service is missing Database dependency.');
    }

    protected function qcache(): ?QueryCache
    {
        if (\property_exists($this, 'qcache') && $this->qcache instanceof QueryCache) {
            return $this->qcache;
        }
        if (\method_exists($this, 'getQueryCache')) {
            $qc = $this->getQueryCache();
            if ($qc instanceof QueryCache) {
                return $qc;
            }
        }
        return null;
    }

    protected function logger(): ?LoggerInterface
    {
        if (\property_exists($this, 'logger') && $this->logger instanceof LoggerInterface) {
            return $this->logger;
        }
        try {
            return $this->db()->getLogger();
        } catch (\Throwable) {
            return null;
        }
    }

    /** ---------- Transactions ---------- */

    /**
     * @template T
     * @param callable(self):T $fn
     * @return T
     */
    protected function txn(callable $fn): mixed
    {
        return $this->db()->transaction(fn () => $fn($this));
    }

    /**
     * Read-only transaction (native on PG, fallback on MySQL).
     *
     * @template T
     * @param callable(self):T $fn
     * @return T
     */
    protected function txnRO(callable $fn): mixed
    {
        return $this->db()->transactionReadOnly(fn () => $fn($this));
    }

    /**
     * Transaction with retries (exponential backoff + jitter) for transient errors.
     *
     * @template T
     * @param callable(self):T $fn
     * @param int $attempts
     * @param int $baseDelayMs
     * @param int $maxDelayMs
     * @param int|null $deadlineMs  Total time budget for all retries (best-effort).
     * @return T
     */
    protected function txnRetry(
        callable $fn,
        int $attempts = 3,
        int $baseDelayMs = 50,
        int $maxDelayMs = 1000,
        ?int $deadlineMs = null
    ): mixed {
        $attempts  = max(1, $attempts);
        $initialMs = max(1, $baseDelayMs);
        $capMs     = max($initialMs, $maxDelayMs);

        return Retry::runAdvanced(
            fn() => $this->txn($fn),
            attempts:   $attempts,
            initialMs:  $initialMs,
            factor:     2.0,
            maxMs:      $capMs,
            jitter:     'equal',
            deadlineMs: $deadlineMs,
            onRetry: function (int $try, \Throwable $e, int $sleepMs, array $ctx): void {
                if ($log = $this->logger()) {
                    try {
                        $log->info('db.txn-retry-transient', [
                            'try'        => $try,
                            'attempts'   => $try + 1, // "completed + next"
                            'sqlstate'   => $ctx['sqlstate'] ?? null,
                            'code'       => $ctx['code'] ?? null,
                            'reason'     => $ctx['reason'] ?? null,
                            'message'    => \substr((string)$e->getMessage(), 0, 200),
                            'nextDelayMs'=> $sleepMs,
                        ]);
                    } catch (\Throwable) {}
                }
            }
        );
    }

    /** ---------- Scoped helpers ---------- */

    /**
     * Advisory lock – run inside the lock (blocking semantics depend on driver).
     *
     * @template T
     * @param callable(self):T $fn
     * @return T
     */
    protected function withLock(string $name, int $timeoutSec, callable $fn): mixed
    {
        $db = $this->db();
        $key = $this->buildLockKey($name);
        $timeoutSec = \max(1, $timeoutSec);

        // On PG some withAdvisoryLock() implementations perform try-lock → emulate blocking wait with deadline.
        if ($db->isPg()) {
            try {
                return Retry::runAdvanced(
                    fn() => $db->withAdvisoryLock($key, 0, fn () => $fn($this)),
                    attempts:   100_000,                 // rely on deadline rather than fixed count
                    initialMs:  25,
                    factor:     2.0,
                    maxMs:      500,
                    jitter:     'equal',
                    deadlineMs: $timeoutSec * 1000,
                    onRetry: function (int $try, \Throwable $e, int $sleepMs, array $ctx) use ($key): void {
                        if ($log = $this->logger()) {
                            try { $log->debug('svc.lock.retry', ['lock'=>$key,'try'=>$try,'sleepMs'=>$sleepMs,'reason'=>$ctx['reason']??null]); } catch (\Throwable) {}
                        }
                    },
                    classifier: function (\Throwable $e): array {
                        $msg = \strtolower((string)$e->getMessage());
                        $busy = \str_contains($msg, 'advisory') || \str_contains($msg, 'pg_try_advisory_lock');
                        if ($busy) {
                            return ['transient'=>true,'reason'=>'lock-busy'];
                        }
                        $c = Retry::classify($e);
                        $reason = $c['reason'] ?? null;
                        return $reason === null
                            ? ['transient' => (bool)($c['transient'] ?? false)]
                            : ['transient' => (bool)($c['transient'] ?? false), 'reason' => (string)$reason];
                    }
                );
            } catch (\Throwable $e) {
                throw new \RuntimeException('advisory-lock deadline exceeded: ' . $key, 0, $e);
            }
        }

        // MySQL/MariaDB → native blocking GET_LOCK with timeout
        return $db->withAdvisoryLock($key, $timeoutSec, fn () => $fn($this));
    }

    /** Non-blocking variant – try to acquire the lock; if busy return ['acquired'=>false]. */
    protected function tryWithLock(string $name, callable $fn): array
    {
        $db = $this->db();
        $key = $this->buildLockKey($name);
        try {
            $res = $db->withAdvisoryLock($key, 0, fn () => $fn($this));
            return ['acquired' => true, 'result' => $res];
        } catch (\Throwable $e) {
            // assume driver signals "busy" via exception; do not rethrow, just mark as not acquired
            return ['acquired' => false, 'result' => null];
        }
    }

    /**
     * Statement timeout v ms pro scope.
     *
     * @template T
     * @param callable(self):T $fn
     * @return T
     */
    protected function withTimeout(int $ms, callable $fn): mixed
    {
        return $this->db()->withStatementTimeout($ms, fn () => $fn($this));
    }

    /**
     * Transaction isolation level for the current scope (e.g., 'serializable', 'repeatable read').
     *
     * @template T
     * @param callable(self):T $fn
     * @return T
     */
    protected function withIsolation(string $level, callable $fn): mixed
    {
        return $this->db()->withIsolationLevel($level, fn () => $fn($this));
    }

    /** ---------- Retry primitive ---------- */

    /**
     * Retry transient errors (deadlock/serialization/timeout).
     *
     * @template T
     * @param callable(self):T $fn
     * @return T
     */
    protected function retry(int $attempts, callable $fn, int $baseDelayMs = 50, int $maxDelayMs = 1000): mixed
    {
        $attempts   = max(1, $attempts);
        $initialMs  = max(1, $baseDelayMs);
        $capMs      = max($initialMs, $maxDelayMs);

        return Retry::runAdvanced(
            // Preserve original callback signature: fn(self):T
            fn() => $fn($this),
            attempts:   $attempts,
            initialMs:  $initialMs,
            factor:     2.0,
            maxMs:      $capMs,
            // Choose "equal" jitter (balanced spread, sensible replacement for small legacy jitter)
            jitter:     'equal',
            deadlineMs: null,
            onRetry: function (int $try, \Throwable $e, int $sleepMs, array $ctx) use ($attempts): void {
                // best-effort log, never throws
                if ($log = $this->logger()) {
                    try {
                        $log->info('db.retry-transient', [
                            'try'        => $try,
                            'attempts'   => $attempts,
                            'sqlstate'   => $ctx['sqlstate'] ?? null,
                            'code'       => $ctx['code'] ?? null,
                            'reason'     => $ctx['reason'] ?? null,
                            'message'    => \substr((string)$e->getMessage(), 0, 200),
                            'nextDelayMs'=> $sleepMs,
                        ]);
                    } catch (\Throwable) {
                        // ignore
                    }
                }
            },
            // Do not pass a custom classifier – Retry::classify already delegates to Core\Database::isTransientPdo
            classifier: null
        );
    }

    /** ---------- Keyset pagination ---------- */

    /**
     * Keyset (seek) pagination via Database::paginateKeyset().
     *
     * @param string $sqlBase   SELECT … FROM … WHERE …  (without ORDER BY/LIMIT; driver adds them)
     * @param array<string,mixed> $params
     * @param string $pkIdent   fully-qualified PK identifier (e.g., 't.id')
     * @param string|int|null $after  last cursor value (seek)
     * @param int $limit
     * @param string|null $pkResultKey  result key name (default = last segment of $pkIdent)
     * @param 'ASC'|'DESC'|'asc'|'desc' $direction
     * @param bool $inclusive   include the row matching $after?
     * @return array{0:array<int,array<string,mixed>>,1:array{colValue:mixed,pkValue:mixed}|null}
     */
    protected function keyset(
        string $sqlBase,
        array $params,
        string $pkIdent,
        string|int|null $after,
        int $limit = 50,
        ?string $pkResultKey = null,
        string $direction = 'DESC',
        bool $inclusive = false
    ): array {
        $direction = strtoupper($direction) === 'ASC' ? 'ASC' : 'DESC';
        $limit = max(1, $limit);

        if ($pkResultKey === null) {
            $pkResultKey = \str_contains($pkIdent, '.')
                ? \substr($pkIdent, (int)\strrpos($pkIdent, '.') + 1)
                : $pkIdent;
        }

        /** @var array{0:array<int,array<string,mixed>>,1:array{colValue:mixed,pkValue:mixed}|null} $res */
        $res = $this->db()->paginateKeyset(
            $sqlBase,
            $params,
            $pkIdent,
            $pkResultKey,
            $after,
            $limit,
            $direction,
            $inclusive
        );
        return $res;
    }

    /** ---------- Explain ---------- */

    /**
     * EXPLAIN / ANALYZE (PG) – driver-agnostic wrapper.
     *
     * @param array<string,mixed> $params
     * @return array<int,array<string,mixed>>
     */
    protected function explain(string $sql, array $params = [], bool $analyze = false): array
    {
        return $this->db()->explainPlan($sql, $params, $analyze);
    }

    /** ---------- Cache helpers ---------- */

    /**
     * @param array<string,mixed> $params
     * @return array<int,array<string,mixed>>
     */
    protected function cacheRows(string $sql, array $params, int|\DateInterval|null $ttl = null): array
    {
        $qc = $this->qcache();
        if (!$qc) {
            return $this->db()->fetchAll($sql, $params);
        }
        return $qc->rememberRows($this->db(), $sql, $params, $ttl);
    }

    /**
     * @param array<string,mixed> $params
     * @return array<string,mixed>|null
     */
    protected function cacheRow(string $sql, array $params, int|\DateInterval|null $ttl = null): ?array
    {
        $qc = $this->qcache();
        if (!$qc) {
            return $this->db()->fetch($sql, $params);
        }
        $key = $qc->key($this->db()->id(), $sql, $params) . ':row';
        /** @var ?array<string,mixed> */
        return $qc->remember($key, $ttl, fn () => $this->db()->fetch($sql, $params));
    }

    /**
     * @param array<string,mixed> $params
     */
    protected function cacheValue(string $sql, array $params, mixed $default = null, int|\DateInterval|null $ttl = null): mixed
    {
        $qc = $this->qcache();
        if (!$qc) {
            return $this->db()->fetchValue($sql, $params, $default);
        }
        $key = $qc->key($this->db()->id(), $sql, $params) . ':val';
        return $qc->remember($key, $ttl, fn () => $this->db()->fetchValue($sql, $params, $default));
    }

    /** ---------- Utilities ---------- */

    /**
     * Deterministic key (useful e.g. for cache namespaces).
     */
    protected function idKey(string $ns, string $id): string
    {
        $dbId = 'db';
        try {
            $db = $this->db();
            if (\method_exists($db, 'id')) {
                $dbId = (string)$db->id();
            }
        } catch (\Throwable) {
            // ignore
        }
        return $ns . ':' . $dbId . ':' . $id;
    }

    /**
     * Transaction wrapper that attaches observability metadata (cross-dialect).
     *
     * @template T
     * @param array<string,mixed> $meta
     * @param callable(self):T $fn
     * @param array<string,mixed> $opts
     * @return T
     */
    protected function txWithMeta(array $meta, callable $fn, array $opts = []): mixed
    {
        return $this->db()->txWithMeta(fn () => $fn($this), $meta, $opts);
    }

    /**
     * Read-only variant of txWithMeta().
     *
     * @template T
     * @param array<string,mixed> $meta
     * @param callable(self):T $fn
     * @param array<string,mixed> $opts
     * @return T
     */
    protected function txRoWithMeta(array $meta, callable $fn, array $opts = []): mixed
    {
        $opts['readOnly'] = true;
        return $this->db()->txWithMeta(fn () => $fn($this), $meta, $opts);
    }
}

/*
Usage in a service class:

use BlackCat\Database\Support\ServiceHelpers;

final class UsersAggregateService
{
    use ServiceHelpers;

    public function __construct(
        private Database $db,
        private ?QueryCache $qcache = null,
        private ?LoggerInterface $logger = null
    ) {}
}
*/
