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
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Exceptions\DdlRetryExceededException;
use BlackCat\Database\Exceptions\ViewVerificationException;
use Psr\Log\LoggerInterface;
use BlackCat\Database\Support\SqlIdentifier as Ident;
use BlackCat\Database\Support\Retry;

/**
 * DdlGuard
 *
 * Robust and safe "CREATE VIEW" guard with:
 * - Advisory locking (protects against concurrent installs/deploys).
 * - Idempotent retries with exponential backoff + jitter.
 * - Directive verification on MySQL/MariaDB (ALGORITHM / SQL SECURITY / DEFINER).
 * - A "fence" check that ensures the view is ready after creation (SHOW CREATE VIEW + LIMIT 0 probe).
 * - Transparent observability through Database::execWithMeta/fetch*WithMeta.
 *
 * Postgres: directives are not validated (it is not useful there) but locking + fencing remain enabled.
 */
final class DdlGuard
{
    private const META_COMPONENT = 'ddlguard';

    public function __construct(
        private Database $db,
        private SqlDialect $dialect,
        private ?LoggerInterface $logger = null
    ) {
        $this->logger ??= $db->getLogger();
    }

    /* ---------------------------------------------------------------------
     * Public API
     * ------------------------------------------------------------------- */

    /**
     * Executes CREATE VIEW with safety checks and verification.
     *
     * @param non-empty-string $stmt  full CREATE VIEW DDL (can contain OR REPLACE/DEFINER/ALGORITHM/SQL SECURITY)
     * @param array{
     *   lockTimeoutSec?:int,
     *   retries?:int,
     *   fenceMs?:int,
     *   dropFirst?:bool,
     *   normalizeOrReplace?:bool,
     *   ignoreDefinerDrift?:bool,
     *   expectedDefiner?:?string
     * } $opts
     */
    public function applyCreateView(string $stmt, array $opts = []): void
    {
        $this->assertCreateView($stmt);

        [$name, $expectAlg, $expectSec, $expectDefRaw] = $this->parseCreateViewHead($stmt);

        if ($this->dialect->isMysql()) {
            $alg = $expectAlg !== null ? \strtoupper($expectAlg) : null;
            if ($alg === null) {
                throw new \InvalidArgumentException('CREATE VIEW is missing ALGORITHM (MERGE or TEMPTABLE required).');
            }
            if ($alg === 'UNDEFINED') {
                throw new \InvalidArgumentException('CREATE VIEW ALGORITHM=UNDEFINED is not allowed; use MERGE or TEMPTABLE.');
            }
        }

        $lockTimeout   = \max(1, (int)($opts['lockTimeoutSec'] ?? 10));
        $retries       = \max(1, (int)($opts['retries'] ?? (int)($_ENV['BC_INSTALLER_VIEW_RETRIES'] ?? 3)));
        $fenceMs       = \max(0, (int)($opts['fenceMs'] ?? (int)($_ENV['BC_VIEW_FENCE_MS'] ?? 600)));
        $dropFirst     = (bool)($opts['dropFirst'] ?? true);
        $normalizeOR   = (bool)($opts['normalizeOrReplace'] ?? true);
        $ignoreDefiner = (bool)($opts['ignoreDefinerDrift'] ?? ($_ENV['BC_VIEW_IGNORE_DEFINER'] ?? '') === '1');
        $expectedDefinerOverride = (\array_key_exists('expectedDefiner', $opts) && \is_string($opts['expectedDefiner']))
            ? $opts['expectedDefiner']
            : null;

        $expectDef = $expectedDefinerOverride ?? $expectDefRaw;
        /** @var non-empty-string $name */
        $name = $name;

        // (Optionally) strip "OR REPLACE" to keep behavior consistent with dropFirst
        $create = $normalizeOR
            ? (\preg_replace('~\bCREATE\s+OR\s+REPLACE\b~i', 'CREATE', $stmt) ?: $stmt)
            : $stmt;

        $this->withInstallerLock($name, $lockTimeout, function () use ($name, $dropFirst, $create, $retries, $fenceMs, $expectAlg, $expectSec, $expectDef, $ignoreDefiner): void {
                try {
                    Retry::runAdvanced(
                        fn() => $this->applyCreateViewOnce(
                            $name,
                            $create,
                            // dropFirst should run on EVERY attempt; without that CREATE (without OR REPLACE) would fail if
                            // a previous attempt created the view and failed only during the fence/verify phase.
                            $dropFirst,
                            $fenceMs,
                            $expectAlg,
                            $expectSec,
                            $expectDef,
                            $ignoreDefiner
                        ),
                        attempts: \max(1, $retries),
                        initialMs: 50,
                        factor: 2.0,
                        maxMs: 1000,
                        jitter: 'decorrelated',
                        onRetry: function (int $attempt, \Throwable $e, int $sleepMs, array $ctx) use ($name): void {
                            try {
                                $this->log('warning', 'applyCreateView retry', [
                                    'view'       => $name,
                                    'attempt'    => $attempt,
                                    'sleep_ms'   => $sleepMs,
                                    'sqlstate'   => Retry::sqlState($e),
                                    'code'       => Retry::vendorCode($e),
                                    'reason'     => $ctx['reason'] ?? null,
                                    'error'      => \substr((string)$e->getMessage(), 0, 300),
                                ]);
                            } catch (\Throwable) {}
                        }
                        // Do not pass a classifier, so the central Retry::classify() heuristic is used
                    );
                } catch (\Throwable $e) {
                    if ($e instanceof ViewVerificationException) {
                        throw $e; // keep the precise reason for the directive drift
                    }
                    throw new DdlRetryExceededException("CREATE VIEW {$name}", $retries, $e);
                }
            }
        );
    }

    /**
     * Performs a SINGLE attempt to create the view (including the optional drop and verification).
     * Does not perform any retries/backoff; the caller handles that through Retry::runAdvanced().
     * Retries run inside the advisory lock.
     * @param non-empty-string $name
     * @param non-empty-string $create  CREATE VIEW ... (possibly already without OR REPLACE, per the option)
     */
    private function applyCreateViewOnce(
        string $name,
        string $create,
        bool $dropFirst,
        int $fenceMs,
        ?string $expectAlg,
        ?string $expectSec,
        ?string $expectDef,
        bool $ignoreDefiner
    ): void {
        if ($dropFirst) {
            $this->dropViewIfExists($name, 'precreate');
        }

        // CREATE VIEW
        $this->execMeta(
            $create,
            [],
            ['component' => self::META_COMPONENT, 'op' => 'create_view', 'view' => $name]
        );

        // Fence – wait until the view becomes readable (MySQL/MariaDB)
        $this->fenceViewReady($name, $fenceMs);

        // Postgres: bez direktiv – hotovo.
        if (!$this->dialect->isMysql()) {
            return;
        }

        // MySQL/MariaDB: verify directives
        $got = $this->currentMySqlDirectives($name);

        $actualAlg = \strtoupper((string)($got['algorithm'] ?? ''));
        if ($actualAlg === 'UNDEFINED') {
            throw ViewVerificationException::drift($name, $got, ['algorithm' => $expectAlg, 'security' => $expectSec, 'definer' => $expectDef]);
        }

        $okAlg = !$expectAlg || $actualAlg === \strtoupper($expectAlg);
        $okSec = !$expectSec || \strtoupper((string)($got['security']  ?? '')) === \strtoupper($expectSec);

        $okDef = true;
        if (!$ignoreDefiner && $expectDef) {
            $expectedNorm = $this->normalizeDefiner($expectDef)
                ?? $this->normalizeDefiner($this->resolveCurrentUser() ?? '');
            $gotNorm      = $this->normalizeDefiner((string)($got['definer'] ?? ''));
            $okDef = $expectedNorm !== null && $expectedNorm === $gotNorm;
        }

        if ($okAlg && $okSec && $okDef) {
            return;
        }

        // Drift -> perform a one-off recreation within the same attempt
        $this->log('warning', 'View directives drift detected; recreating', [
            'view'   => $name,
            'expect' => ['algorithm' => $expectAlg, 'security' => $expectSec, 'definer' => $expectDef],
            'got'    => $got,
        ]);

        $this->dropViewIfExists($name, 'drift');

        $this->execMeta(
            $create,
            [],
            ['component' => self::META_COMPONENT, 'op' => 'create_view', 'view' => $name, 'reason' => 'recreate']
        );

        $this->fenceViewReady($name, $fenceMs);

        $got2 = $this->currentMySqlDirectives($name);

        $actualAlg2 = \strtoupper((string)($got2['algorithm'] ?? ''));
        if ($actualAlg2 === 'UNDEFINED') {
            throw ViewVerificationException::drift($name, $got2, ['algorithm' => $expectAlg, 'security' => $expectSec, 'definer' => $expectDef]);
        }

        $okAlg = !$expectAlg || $actualAlg2 === \strtoupper($expectAlg);
        $okSec = !$expectSec || \strtoupper((string)($got2['security']  ?? '')) === \strtoupper($expectSec);

        $okDef = true;
        if (!$ignoreDefiner && $expectDef) {
            $expectedNorm = $this->normalizeDefiner($expectDef)
                ?? $this->normalizeDefiner($this->resolveCurrentUser() ?? '');
            $gotNorm      = $this->normalizeDefiner((string)($got2['definer'] ?? ''));
            $okDef = $expectedNorm !== null && $expectedNorm === $gotNorm;
        }

        if ($okAlg && $okSec && $okDef) {
            return;
        }

        // Still wrong after one recreation -> throw a verification exception (non-transient).
        throw ViewVerificationException::drift(
            $name,
            $got2,
            ['algorithm' => $expectAlg, 'security' => $expectSec, 'definer' => $expectDef]
        );
    }

    /**
     * "Fence" – waits until the view metadata is available (SHOW CREATE VIEW + LIMIT 0 probe).
     * MySQL/MariaDB-only; noop on PG.
     */
    public function fenceViewReady(string $name, int $maxWaitMs = 600): void
    {
        if (!$this->dialect->isMysql() || $maxWaitMs <= 0) {
            return;
        }

        // Use a validated name plus a pre-quoted identifier
        $this->assertQualifiedIdent($name);
        $qiName = Ident::qi($this->db, $name);

        $deadline = \microtime(true) + ($maxWaitMs / 1000.0);
        do {
            $ddl = $this->showCreateView($name);
            if ($ddl !== null) {
                try {
                    // LIMIT 0 verifies schema/metadata availability (no parameters; identifier is safely quoted already)
                    $sql = sprintf('SELECT * FROM %s LIMIT 0', $qiName);
                    $this->db->withStatement($sql, static fn($s) => true);
                    return;
                } catch (\Throwable) {
                    // still not ready yet
                }
            }
            \usleep(30_000);
        } while (\microtime(true) < $deadline);

        $this->log('warning', 'fenceViewReady timeout', ['view' => $name, 'wait_ms' => $maxWaitMs]);
    }

    /**
     * Fast view verification (MySQL/MariaDB); always true on PG.
     * @param array{algorithm?:string,security?:string,definer?:string|null} $expect
     */
    public function verifyView(string $name, array $expect): bool
    {
        if (!$this->dialect->isMysql()) {
            return true;
        }

        $got   = $this->currentMySqlDirectives($name);
        $alg = \strtoupper((string)($got['algorithm'] ?? ''));
        if ($alg === 'UNDEFINED') {
            return false;
        }

        $okAlg = empty($expect['algorithm']) || $alg === \strtoupper((string)$expect['algorithm']);
        $okSec = empty($expect['security'])  || \strtoupper((string)($got['security']  ?? '')) === \strtoupper((string)$expect['security']);

        $okDef = true;
        if (\array_key_exists('definer', $expect)) {
            $exp = $this->normalizeDefiner((string)$expect['definer'])
                ?? $this->normalizeDefiner($this->resolveCurrentUser() ?? '');
            $gotN = $this->normalizeDefiner((string)($got['definer'] ?? ''));
            $okDef = $exp !== null && $exp === $gotN;
        }

        return $okAlg && $okSec && $okDef;
    }

    /* ---------------------------------------------------------------------
     * Internals
     * ------------------------------------------------------------------- */

    private function lockKey(string $name): string
    {
        // GET_LOCK has ~64 character limit → shorten and add a hash for stability
        $base = (string)\preg_replace('~[^A-Za-z0-9_.:-]+~', '.', $name ?: 'view');
        if (\strlen($base) > 40) {
            $base = \substr($base, 0, 24) . '|' . \substr(\hash('sha256', $base), 0, 12);
        }
        return 'view:' . $base;
    }

    /**
     * Universal advisory-lock wrapper that also waits on PG.
     * - MySQL/MariaDB: Database::withAdvisoryLock blocks (GET_LOCK with timeout).
     * - PostgreSQL: Database::withAdvisoryLock is typically try-lock → retry with backoff until the timeout.
     *
     * @param callable():mixed $fn
     */
    private function withInstallerLock(string $lockName, int $timeoutSec, callable $fn): mixed
    {
        /** @var string $lockLabel */
        $lockLabel = (string)$lockName;
        $key = $this->lockKey($lockName);
        $timeoutSec = \max(1, $timeoutSec);

        if ($this->dialect->isPg()) {
            // For PostgreSQL we first attempt a short try-lock loop to catch busy locks,
            // then one blocking attempt with a small timeout to avoid 0-attempt failures.
            $classifier = function (\Throwable $e): array {
                $msg = \strtolower((string)$e->getMessage());
                $busy = \str_contains($msg, 'pg_try_advisory_lock') || \str_contains($msg, 'advisory_lock');
                if ($busy) {
                    return ['transient' => true, 'reason' => 'lock-busy'];
                }
                $c = Retry::classify($e);
                $reason = $c['reason'] ?? null;
                return $reason === null
                    ? ['transient' => (bool)($c['transient'] ?? false)]
                    : ['transient' => (bool)($c['transient'] ?? false), 'reason' => (string)$reason];
            };

            try {
                // Phase 1: fast try-lock retries until deadline
                $result = Retry::runAdvanced(
                    fn() => $this->db->withAdvisoryLock($key, 1, $fn),
                    attempts: 5_000,
                    initialMs: 10,
                    factor: 1.5,
                    maxMs: 200,
                    jitter: 'equal',
                    deadlineMs: \max(250, $timeoutSec * 1000),
                    onRetry: function (int $attempt, \Throwable $e, int $sleepMs, array $ctx) use ($lockLabel): void {
                        $this->log('debug', 'advisory lock busy (retry)', [
                            'lock'     => $lockLabel,
                            'attempt'  => $attempt,
                            'sleep_ms' => $sleepMs,
                            'reason'   => $ctx['reason'] ?? null,
                        ]);
                    },
                    classifier: $classifier
                );
                return $result;
            } catch (\Throwable $e) {
                // Phase 2: one blocking attempt with timeout
                try {
                    return $this->db->withAdvisoryLock($key, $timeoutSec, $fn);
                } catch (\Throwable $e2) {
                    // Final fallback: run without the advisory lock (best effort) to avoid zero-attempt failures.
                    try {
                        $this->log('warning', 'advisory lock fallback (running without lock)', ['lock' => $lockLabel, 'error' => $e2->getMessage()]);
                    } catch (\Throwable) {}
                    return $fn();
                }
            }
        }

        // MySQL/MariaDB – GET_LOCK(timeout) blocks and Database::withAdvisoryLock handles that
        return $this->db->withAdvisoryLock($key, $timeoutSec, $fn);
    }

    /** @return array{0:string,1:?string,2:?string,3:?string} [name, algorithm, security, definer] */
    private function parseCreateViewHead(string $stmt): array
    {
        // View name (schema optional) located after the VIEW keyword and before AS
        if (!\preg_match('~\bVIEW\s+([`"]?[A-Za-z0-9_]+[`"]?(?:\.[`"]?[A-Za-z0-9_]+[`"]?)?)\s+AS\b~i', $stmt, $m)) {
            throw new \InvalidArgumentException(
                'Cannot parse VIEW name from statement head=' . \substr(\trim($stmt), 0, 160)
            );
        }
        $name = (string)\preg_replace('~[`"]~', '', $m[1]); // strip quotes, keep dot

        $alg = null; $sec = null; $def = null;
        if (\preg_match('~\bALGORITHM\s*=\s*(UNDEFINED|MERGE|TEMPTABLE)\b~i', $stmt, $mm)) { $alg = \strtoupper($mm[1]); }
        if (\preg_match('~\bSQL\s+SECURITY\s+(DEFINER|INVOKER)\b~i',        $stmt, $mm)) { $sec = \strtoupper($mm[1]); }
        if (\preg_match('~\bDEFINER\s*=\s*([^\s]+)~i',                      $stmt, $mm)) { $def = $mm[1]; }

        return [$name, $alg, $sec, $def];
    }

    /** @return array{algorithm:?(string),security:?(string),definer:?(string)} */
    private function currentMySqlDirectives(string $name): array
    {
        $ddl = $this->showCreateView($name);
        $out = ['algorithm' => null, 'security' => null, 'definer' => null];
        if ($ddl === null) {
            return $out;
        }

        if (\preg_match('~\bALGORITHM\s*=\s*(UNDEFINED|MERGE|TEMPTABLE)\b~i', $ddl, $m)) { $out['algorithm'] = \strtoupper($m[1]); }
        if (\preg_match('~\bSQL\s+SECURITY\s+(DEFINER|INVOKER)\b~i',        $ddl, $m)) { $out['security']  = \strtoupper($m[1]); }
        if (\preg_match('~\bDEFINER\s*=\s*([^\s]+)~i',                      $ddl, $m)) { $out['definer']   = $m[1]; }
        return $out;
    }

    private function showCreateView(string $name): ?string
    {
        if (!$this->dialect->isMysql()) {
            return null;
        }

        $this->assertQualifiedIdent($name);
        $qiName = Ident::qi($this->db, $name);

        try {
            $sql = sprintf('SHOW CREATE VIEW %s', $qiName);
            $row = $this->fetchRowMeta($sql, [], [
                'component' => self::META_COMPONENT, 'op' => 'show_create_view', 'view' => $name
            ]) ?? [];

            // Different drivers return different keys/order; try known variants:
            // - 'Create View' (MySQL)
            // - index 1 (some pdo_mysql drivers)
            // - 'Create View' / 'Create View ' (trim)
            $candidates = [
                'Create View',
                'Create View ',
                'Create view',
                1,
            ];
            foreach ($candidates as $k) {
                if (\array_key_exists((string)$k, $row)) {
                    return (string)$row[(string)$k];
                }
            }
            // Fallback – grab the second value in the row if it exists
            $vals = \array_values($row);
            return isset($vals[1]) ? (string)$vals[1] : null;
        } catch (\Throwable) {
            return null;
        }
    }

    private function normalizeDefiner(?string $s): ?string
    {
        if (!$s) {
            return null;
        }
        $x = \trim($s);
        if (\stripos($x, 'current_user') === 0) {
            // Ignore specific user/host – treat it as a match
            return 'CURRENT_USER';
        }
        // SHOW CREATE VIEW on MySQL/MariaDB typically returns: DEFINER=`user`@`host`
        if (\preg_match('~`([^`]*)`@`([^`]*)`~', $x, $m)) {
            return $m[1] . '@' . $m[2];
        }
        // Remove backticks/quotes, keep "user@host"
        $x = \str_replace(['`','"'], '', $x);
        return $x;
    }

    private function resolveCurrentUser(): ?string
    {
        try {
            if ($this->dialect->isMysql()) {
                $v = (string)$this->fetchValueMeta(
                    'SELECT CURRENT_USER()',
                    [],
                    ['component' => self::META_COMPONENT, 'op' => 'current_user']
                );

                return $this->normalizeDefiner($v);
            }
        } catch (\Throwable) {
            // ignore
        }
        return null;
    }

    private function dropViewIfExists(string $name, string $reason): void
    {
        try {
            $this->assertQualifiedIdent($name);
            $qiName = Ident::qi($this->db, $name);
            $sql = sprintf('DROP VIEW IF EXISTS %s', $qiName);
            $this->execMeta($sql, [], [
                'component' => self::META_COMPONENT, 'op' => 'drop_view', 'view' => $name, 'reason' => $reason
            ]);
        } catch (\Throwable $e) {
            $this->log('warning', 'DROP VIEW failed (ignoring)', ['view' => $name, 'err' => $e->getMessage()]);
        }
    }

    private function log(string $level, string $msg, array $ctx = []): void
    {
        if ($this->logger) {
            $this->logger->log($level, '[DdlGuard] ' . $msg, $ctx);
            return;
        }
        \error_log('[DdlGuard][' . \strtoupper($level) . '] ' . $msg . ' ' . \json_encode($ctx));
    }

    private function assertCreateView(string $stmt): void
    {
        $h = \strtoupper(\ltrim($stmt));
        if (\strpos($h, 'CREATE') !== 0) {
            throw new \InvalidArgumentException('Statement must start with CREATE … VIEW');
        }
        if (!\preg_match('~\bCREATE\b.+\bVIEW\b~i', $stmt)) {
            throw new \InvalidArgumentException('Statement must contain CREATE VIEW');
        }
    }

    /**
     * Quick validation of a qualified identifier (optional schema + name)
     * before passing it to Ident::qi(). Guards against empty strings
     * and odd whitespace; qi() performs the actual quoting.
     */
    private function assertQualifiedIdent(string $ident): void
    {
        $x = \trim($ident);
        if ($x === '') {
            throw new \InvalidArgumentException('Empty identifier.');
        }
        // Allow a.b, "a".b, etc. – coarse check for disallowed whitespace inside
        if (\preg_match('~[\r\n\t]~', $x)) {
            throw new \InvalidArgumentException('Invalid whitespace in identifier.');
        }
    }

    private function execMeta(string $sql, array $params = [], array $meta = []): void
    {
        if (\method_exists($this->db, 'execWithMeta')) {
            $this->db->execWithMeta($sql, $params, $meta);
            return;
        }
        if (\method_exists($this->db, 'exec')) {
            if ($params) {
                $this->db->exec($sql, $params);
            } else {
                $this->db->exec($sql);
            }
            return;
        }
        if (\method_exists($this->db, 'query')) {
            $this->db->query($sql);
        }
    }

    private function fetchRowMeta(string $sql, array $params = [], array $meta = []): ?array
    {
        return $this->db->fetchRowWithMeta($sql, $params, $meta);
    }

    private function fetchValueMeta(string $sql, array $params = [], array $meta = []): mixed
    {
        return $this->db->fetchValueWithMeta($sql, $params, null, $meta);
    }
}
