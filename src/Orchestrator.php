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

namespace BlackCat\Database;

use BlackCat\Core\Database;
use BlackCat\Database\Support\Observability;
use Psr\Log\LoggerInterface;
use BlackCat\Database\Support\SqlPreview;
use BlackCat\Database\Support\Retry;

final class Orchestrator
{
    public function __construct(
        private readonly Runtime $rt,
        private ?LoggerInterface $logger = null
    ) {
        $this->logger = $this->logger ?? $rt->logger();
    }

    private function db(): Database { return $this->rt->db(); }
    private function dialect(): SqlDialect { return $this->rt->dialect(); }

    /**
     * Executes an iterable set of SQL statements.
     * When $dryRun is enabled the SQL is only logged, never executed.
     *
     * PostgreSQL runs the whole batch inside a SERIALIZABLE transaction.
     * MySQL/MariaDB executes statements without a transaction because DDL triggers implicit commits.
     *
     * @param iterable<string|\Stringable> $statements SQL statements to execute in order
     * @param bool $dryRun whether to log instead of executing
     * @param array<string,mixed> $meta observability metadata propagated to Database::execWithMeta
     */
    public function run(iterable $statements, bool $dryRun = false, array $meta = []): void
    {
        $db   = $this->db();
        $meta = ['svc' => 'orchestrator', 'op' => 'ddl.apply'] + $meta;

        $lockName = 'schema:migrate:' . $db->id();
        $lockSec  = (int)($_ENV['BC_ORCH_LOCK_TIMEOUT_SEC'] ?? 30);
        $timeoutMs = (int)($_ENV['BC_ORCH_STMT_TIMEOUT_MS'] ?? 120_000);   // PG tx timeout / MySQL session statement timeout

        $this->withInstallerLock($db, $lockName, $lockSec, function () use ($db, $statements, $dryRun, $meta, $timeoutMs) {

            // PostgreSQL: execute everything in a single transaction
            if ($db->isPg()) {
                $db->txWithMeta(function (Database $db) use ($statements, $dryRun, $meta, $timeoutMs) {
                    return $db->withStatementTimeout($timeoutMs, function () use ($db, $statements, $dryRun, $meta) {
                        $i = 0;
                        foreach ($statements as $sql) {
                            $sql = trim((string)$sql);
                            // Skip empty lines and manual BEGIN/COMMIT statements inside the batch
                            if ($sql === '' || preg_match('~^\s*(BEGIN|COMMIT|ROLLBACK)\b~i', $sql)) continue;

                            if ($dryRun) {
                                $this->logger?->info('ddl-dry-run', [
                                    'step' => $i++,
                                    'sql_preview' => SqlPreview::preview($sql),
                                    'len'         => strlen($sql),
                                ] + $meta);
                                continue;
                            }

                            try {
                                $t0 = microtime(true);
                                $db->execWithMeta($sql, [], ['op' => 'ddl.step'] + $meta);
                                $this->logger?->debug('ddl-step-ok', [
                                    'step' => $i++,
                                    'ms'   => Observability::ms($t0),
                                ] + $meta);
                            } catch (\Throwable $e) {
                                $err = Observability::errorFields($e);
                                $this->logger?->error('ddl-step-error', [
                                    'step'        => $i,
                                    'sql_preview' => SqlPreview::preview($sql),
                                    'len'         => strlen($sql),
                                ] + $err + $meta);
                                throw $e;
                            }
                        }
                        return null;
                    });
                }, $meta, [
                    'timeoutMs' => $timeoutMs,
                    'isolation' => 'serializable',
                ]);
                return null;
            }

            // MySQL / MariaDB 10.4: run without a transaction but enforce a session statement timeout
            return $db->withStatementTimeout($timeoutMs, function () use ($db, $statements, $dryRun, $meta) {
                $i = 0;
                foreach ($statements as $sql) {
                    $sql = trim((string)$sql);
                    if ($sql === '') continue;

                    if ($dryRun) {
                        $this->logger?->info('ddl-dry-run', [
                            'step'        => $i++,
                            'sql_preview' => SqlPreview::preview($sql),
                            'len'         => strlen($sql),
                        ] + $meta);
                        continue;
                    }

                    try {
                        // Heads-up: DDL on MySQL/MariaDB always performs an implicit commit.
                        $t0 = microtime(true);
                        $db->execWithMeta($sql, [], ['op' => 'ddl.step'] + $meta);
                        $this->logger?->debug('ddl-step-ok', [
                            'step' => $i++,
                            'ms'   => Observability::ms($t0),
                        ] + $meta);
                    } catch (\Throwable $e) {
                        $err = Observability::errorFields($e);
                        $this->logger?->error('ddl-step-error', [
                            'step'        => $i,
                            'sql_preview' => SqlPreview::preview($sql),
                            'len'         => strlen($sql),
                        ] + $err + $meta);
                        throw $e;
                    }
                }
                return null;
            });
        });
    }

    public function installOrUpgradeAll(Registry $registry): void
    {
        $db   = $this->db();
        $meta = Observability::withDefaults(
            Observability::ensureCorr(['svc'=>'orchestrator','op'=>'schema.install_all']), $db
        );

        $lockName = 'schema:migrate:' . $db->id();

        $this->withInstallerLock($db, $lockName, (int)($_ENV['BC_ORCH_LOCK_TIMEOUT_SEC'] ?? 30), function () use ($db, $registry, $meta) {
            // PostgreSQL: transactional DDL; MySQL/MariaDB: execute without a transaction
            if ($db->isPg()) {
                $db->txWithMeta(function(Database $db) use ($registry) {
                    $db->withStatementTimeout(60_000, function() use ($registry) {
                        $inst = new Installer($this->db(), $this->dialect());
                        $registry->installOrUpgradeAll($inst);
                        return null;
                    });
                    return null;
                }, $meta, ['isolation'=>'serializable']);
            } else {
                $db->withStatementTimeout(60_000, function() use ($registry) {
                    $inst = new Installer($this->db(), $this->dialect());
                    $registry->installOrUpgradeAll($inst);
                    return null;
                });
            }
            return null;
        });
    }

    /**
     * Returns installation status for every registered module along with an aggregate summary.
     *
     * @return array{modules:array<int,array<string,mixed>>,summary:array<string,int>,dbId:string,serverVersion:?string}
     */
    public function status(Registry $registry): array
    {
        $db = $this->db();
        $inst = new Installer($db, $this->dialect());

        $mods = $registry->all();
        $st   = $inst->status($mods);

        $summary = ['total'=>count($mods), 'needsInstall'=>0, 'needsUpgrade'=>0];
        foreach ($st as $row) {
            if ($row['needsInstall']) $summary['needsInstall']++;
            if ($row['needsUpgrade']) $summary['needsUpgrade']++;
        }
        return [
            'modules'       => $st,
            'summary'       => $summary,
            'dbId'          => $db->id(),
            'serverVersion' => $db->serverVersion(),
        ];
    }

    public function installOrUpgradeOne(Contracts\ModuleInterface $m): void
    {
        $db   = $this->db();
        $meta = Observability::withDefaults(
            Observability::ensureCorr(['svc'=>'orchestrator','op'=>'schema.install_one','module'=>$m->name()]),
            $db
        );
        $lockName = 'schema:migrate:' . $db->id();

        $this->withInstallerLock($db, $lockName, (int)($_ENV['BC_ORCH_LOCK_TIMEOUT_SEC'] ?? 30), function () use ($db, $m, $meta) {
            if ($db->isPg()) {
                $db->txWithMeta(function(Database $db) use ($m) {
                    $db->withStatementTimeout(60_000, function() use ($m) {
                        $inst = new Installer($this->db(), $this->dialect());
                        $inst->installOrUpgrade($m);
                        return null;
                    });
                    return null;
                }, $meta, ['isolation'=>'serializable']);
            } else {
                $db->withStatementTimeout(60_000, function() use ($m) {
                    $inst = new Installer($this->db(), $this->dialect());
                    $inst->installOrUpgrade($m);
                    return null;
                });
            }
            return null;
        });
    }

    /**
     * Unified advisory-lock helper.
     * - MySQL/MariaDB: relies on Database::withAdvisoryLock (blocking GET_LOCK with timeout)
     * - PostgreSQL: emulates blocking behavior with a try-lock wrapped in Retry until the deadline.
     *
     * @param Database $db connection used for locking
     * @param string $lockName logical name of the lock
     * @param int $timeoutSec maximum time to wait for the lock in seconds
     * @param callable():mixed $fn callback executed while the lock is held
     * @return mixed result returned by the callback
     */
    private function withInstallerLock(Database $db, string $lockName, int $timeoutSec, callable $fn): mixed
    {
        $lockName = $this->sanitizeLockName($lockName);
        $timeoutSec = max(1, $timeoutSec);

        if (!$db->isPg()) {
            return $db->withAdvisoryLock($lockName, $timeoutSec, $fn);
        }

        // PostgreSQL: Database::withAdvisoryLock() performs a try-lock (timeout=0), so wrap it in Retry with a deadline.
        return Retry::runAdvanced(
            fn() => $db->withAdvisoryLock($lockName, 0, $fn),
            attempts: 10_000,
            initialMs: 25,
            factor: 2.0,
            maxMs: 500,
            jitter: 'equal',
            deadlineMs: $timeoutSec * 1000,
            onRetry: function (int $attempt, \Throwable $e, int $sleepMs) use ($lockName): void {
                $this->logger?->debug('orch-lock-retry', [
                    'lock' => $lockName, 'attempt' => $attempt, 'sleep_ms' => $sleepMs
                ]);
            },
            classifier: [$this, 'classifyLockError']
        );
    }

    private function sanitizeLockName(string $s): string
    {
        $x = trim($s);
        // Remove whitespace and unusual characters; keep a stable schema:migrate:<dbid>-style key.
        $x = preg_replace('~[^A-Za-z0-9_.:-]+~', '.', $x) ?? $x;
        if (strlen($x) > 64) {
            $x = substr($x, 0, 40) . '|' . substr(hash('sha256', $x), 0, 12);
        }
        return $x;
    }

    /**
     * @return array{transient: bool, reason?: string}
     * @phpstan-return array{transient: bool, reason?: string}
     */
    private function classifyLockError(\Throwable $e): array
    {
        $msg = strtolower((string)$e->getMessage());
        $busy = str_contains($msg, 'pg_try_advisory_lock') || str_contains($msg, 'advisory_lock');
        if ($busy) {
            return ['transient'=>true,'reason'=>'lock-busy'];
        }
        $classified = Retry::classify($e);
        $reason = $classified['reason'] ?? null;
        return $reason === null
            ? ['transient' => (bool)($classified['transient'] ?? false)]
            : ['transient' => (bool)($classified['transient'] ?? false), 'reason' => (string)$reason];
    }
}
