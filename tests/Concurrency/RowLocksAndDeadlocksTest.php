<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Concurrency;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;
use BlackCat\Database\Tests\Support\ConnFactory;

/**
 * Testy konkurence: row lock timeout, NOWAIT/SKIP LOCKED a deadlock detekce.
 */
final class RowLocksAndDeadlocksTest extends TestCase
{
    private static ?string $table = null;
    private static ?string $pk = 'id';
    private static ?string $updCol = null;

    public static function setUpBeforeClass(): void
    {
        // modular install (idempotent)
        DbHarness::ensureInstalled();

        // find a "safe" table with identity PK 'id' and an updatable column (via Definitions only)
        foreach (glob(__DIR__ . '/../../packages/*/src/Definitions.php') as $df) {
            require_once $df;
            if (!preg_match('~[\\\\/]packages[\\\\/]([A-Za-z0-9_]+)[\\\\/]src[\\\\/]Definitions\.php$~i', $df, $m)) continue;
            $ns = $m[1];
            $defs = "BlackCat\\Database\\Packages\\{$ns}\\Definitions";
            if (!class_exists($defs)) continue;
            if (!$defs::isIdentityPk()) continue;
            if ($defs::pk() !== 'id') continue;

            $table = $defs::table();
            if (method_exists($defs, 'isRowLockSafe') && !$defs::isRowLockSafe()) continue;
            [$sample, $updatable] = RowFactory::makeSample($table);
            if ($sample === null) continue; // required FK etc. - skip

            // pick a regular updatable column from Definitions (!= id, != audit)
            $bad    = ['id', 'created_at', 'updated_at', 'deleted_at', (string)$defs::versionColumn()];
            $updCol = null;
            foreach ((array)$defs::columns() as $name) {
                $name = (string)$name;
                if ($name === '' || in_array($name, $bad, true)) continue;
                $updCol = $name; break;
            }
            if (!$updCol) continue;

            self::$table = $table;
            self::$updCol = $updCol;
            break;
        }
        if (!self::$table) {
            self::markTestSkipped('No safe table with identity PK found.');
        }
    }

    private function insertRow(\PDO $pdo): int
    {
        $ins = RowFactory::insertSample(self::$table);
        return (int)$ins['pk'];
    }

    public function test_row_lock_wait_timeout_then_success_after_release(): void
    {
        $this->assertNotNull(self::$table);
        $pdo1 = ConnFactory::newPdo();
        $pdo2 = ConnFactory::newPdo();

        $id = $this->insertRow($pdo1);

        // TX1: lock the row
        $pdo1->beginTransaction();
        $pdo1->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE")->execute([':id'=>$id]);

        // TX2: pokus o update -> lock timeout
        $pdo2->beginTransaction();
        ConnFactory::setShortLockTimeout($pdo2, 1000);
        $thrown = null;
        try {
            $pdo2->prepare("UPDATE ".self::$table." SET ".self::$updCol." = ".self::$updCol." WHERE id=:id")
                 ->execute([':id'=>$id]);
            // If no timeout occurred, fail
            $this->fail('Expected lock wait timeout, but UPDATE succeeded');
        } catch (\Throwable $e) {
            $thrown = $e;
        }
        $this->assertNotNull($thrown, 'Lock wait timeout did not happen');
        // PG: error aborts the entire TX -> reset it or you'll hit 25P02
        if ($pdo2->inTransaction()) {
            try { $pdo2->rollBack(); } catch (\Throwable $ignore) {}
        }
        $pdo2->beginTransaction();

        // release the lock and retry
        $pdo1->commit();
        $pdo2->prepare("UPDATE ".self::$table." SET ".self::$updCol." = ".self::$updCol." WHERE id=:id")
             ->execute([':id'=>$id]);
        $pdo2->commit();
    }

    public function test_nowait_and_skip_locked(): void
    {
        $this->assertNotNull(self::$table);
        $pdo1 = ConnFactory::newPdo();
        $pdo2 = ConnFactory::newPdo();

        $id = $this->insertRow($pdo1);

        $pdo1->beginTransaction();
        $pdo1->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE")->execute([':id'=>$id]);

        $pdo2->beginTransaction();
        // NOWAIT -> immediate error
        $err = null;
        try {
            $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE NOWAIT")->execute([':id'=>$id]);
            $this->fail('NOWAIT should have failed on locked row');
        } catch (\Throwable $e) { $err = $e; }
        $this->assertNotNull($err, 'NOWAIT did not raise');

        // PG: NOWAIT error aborts the transaction -> start a clean TX for SKIP LOCKED
        if ($pdo2->inTransaction()) {
            try { $pdo2->rollBack(); } catch (\Throwable $ignore) {}
        }
        $pdo2->beginTransaction();

        // --- SKIP LOCKED / compatible branch ---
        // Goal: avoid blocking and do not return a locked row.
        // 1) Try native SKIP LOCKED (PG, MySQL 8+). If MariaDB reports syntax error, go to fallback.
        $rows = null;

        try {
            $stmt = $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE SKIP LOCKED");
            $stmt->execute([':id'=>$id]);
            $rows = $stmt->fetchAll();
        } catch (\PDOException $e) {
            $sqlstate = (string)($e->errorInfo[0] ?? '');
            $errno    = (int)   ($e->errorInfo[1] ?? 0);
            $msg      = $e->getMessage();

            // MariaDB without SKIP LOCKED: syntax error (1064/42000) -> use NOWAIT as a "skip" emulation.
            $unsupported = ($errno === 1064)            // SQL syntax error
            || ($errno === 1235)            // not supported yet
            || ($sqlstate === '42000')      // syntax error or access violation
            || ($sqlstate === 'HY000' && stripos($msg, 'not supported') !== false)
            || stripos($msg, 'SKIP LOCKED') !== false;

            if (!$unsupported) {
                throw $e; // different error, do not mask it
            }

            // 2) Fallback: FOR UPDATE NOWAIT (non-blocking). If the row is locked it throws immediately -> treat as "nothing to fetch".
            try {
                $stmt = $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE NOWAIT");
                $stmt->execute([':id'=>$id]);
                $rows = $stmt->fetchAll(); // if it wasn't locked after all, return rows
            } catch (\PDOException $_) {
                $rows = []; // locked -> emulated "skip"
            }
        }

        $this->assertIsArray($rows);
        $this->assertCount(0, $rows, 'Non-blocking path must not return the locked row');

        $pdo1->commit();
        $pdo2->commit();
    }

    public function test_deadlock_detection(): void
    {
        $this->assertNotNull(self::$table);
        $pdo = ConnFactory::newPdo();
        $idA = $this->insertRow($pdo);
        $idB = $this->insertRow($pdo);

        // Prefer the regular PHP CLI for the worker (phpdbg swallows exit codes on some setups).
        $phpBin = PHP_BINARY;
        if (PHP_SAPI === 'phpdbg' && is_string(PHP_BINDIR)) {
            $candidate = rtrim(PHP_BINDIR, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'php';
            if (is_file($candidate) && is_executable($candidate)) {
                $phpBin = $candidate;
            }
        }
        $php = escapeshellarg($phpBin) . ' -d display_errors=1 -d error_reporting=32767';
        $script = escapeshellarg(__DIR__ . '/../Support/deadlock_worker.php');
        $table  = escapeshellarg(self::$table);
        $col    = escapeshellarg(self::$updCol);

        $cmdA = "$script $table $col $idA $idB A";
        $cmdB = "$script $table $col $idA $idB B";

        $desc = [['pipe','r'],['pipe','w'],['pipe','w']];

        // Normalizuj BC_DB (default pg)
        $norm = match (strtolower((string)(getenv('BC_DB') ?: ''))) {
            'mysql', 'mariadb'                               => 'mysql',
            'pg', 'pgsql', 'postgres', 'postgresql', ''      => 'pg',
            default                                          => 'pg',
        };

        // Base: inherit parent's environment (including phpunit.xml variables)
        $env = $_ENV;
        $env['BC_DB'] = $norm;
        // Child processes MUST NOT reinstall bc_compat -> avoids "tuple concurrently updated"
        $env['BC_SKIP_COMPAT'] = '1';
        // ensure PATH/HOME even if $_ENV is empty
        if (!isset($env['PATH']) || $env['PATH'] === '') { $env['PATH'] = getenv('PATH') ?: ''; }
        if (!isset($env['HOME']) || $env['HOME'] === '') { $env['HOME'] = getenv('HOME') ?: ''; }

        // Harden DSN per target backend (inside Docker network host MUST be service name)
        if ($norm === 'pg') {
            // if PG_DSN missing or pointing to localhost/127.0.0.1, rewrite to service "postgres"
            $pgDsn = $env['PG_DSN'] ?? (getenv('PG_DSN') ?: '');
            if ($pgDsn === '' || preg_match('~host\s*=\s*(127\.0\.0\.1|localhost)~i', $pgDsn)) {
                $db   = $env['PGDATABASE'] ?? (getenv('PGDATABASE') ?: 'test');
                $port = $env['PGPORT']     ?? (getenv('PGPORT') ?: '5432');
                $env['PG_DSN'] = "pgsql:host=postgres;port={$port};dbname={$db}";
            }
            // ensure user/password/schema even when absent from $_ENV
            $env['PG_USER']      = $env['PG_USER']      ?? (getenv('PG_USER')      ?: 'postgres');
            $env['PG_PASS']      = $env['PG_PASS']      ?? (getenv('PG_PASS')      ?: 'postgres');
            $env['BC_PG_SCHEMA'] = $env['BC_PG_SCHEMA'] ?? (getenv('BC_PG_SCHEMA') ?: 'public');

            // if DSN missing or pointing to localhost, rewrite to service name
            $pgDsn = $env['PG_DSN'] ?? (getenv('PG_DSN') ?: '');
            if ($pgDsn === '' || preg_match('~host\s*=\s*(127\.0\.0\.1|localhost)~i', $pgDsn)) {
                $db   = $env['PGDATABASE'] ?? (getenv('PGDATABASE') ?: 'test');
                $port = $env['PGPORT']     ?? (getenv('PGPORT')     ?: '5432');
                $env['PG_DSN'] = "pgsql:host=postgres;port={$port};dbname={$db}";
            }

            // avoid ambiguity - drop MySQL variables
            unset($env['MYSQL_DSN'], $env['MYSQL_USER'], $env['MYSQL_PASS']);

        } else {
            // MySQL/MariaDB variant - same rule
            // ensure user/password even if missing in $_ENV
            $env['MYSQL_USER'] = $env['MYSQL_USER'] ?? (getenv('MYSQL_USER') ?: 'root');
            $env['MYSQL_PASS'] = $env['MYSQL_PASS'] ?? (getenv('MYSQL_PASS') ?: 'root');
            $myDsn = $env['MYSQL_DSN'] ?? (getenv('MYSQL_DSN') ?: '');
            if ($myDsn === '' || preg_match('~host\s*=\s*(127\.0\.0\.1|localhost)~i', $myDsn)) {
                $db   = $env['MYSQL_DATABASE'] ?? (getenv('MYSQL_DATABASE') ?: 'test');
                $port = $env['MYSQL_PORT']     ?? (getenv('MYSQL_PORT')     ?: '3306');
                $env['MYSQL_DSN'] = "mysql:host=mysql;port={$port};dbname={$db};charset=utf8mb4";
            }
            unset($env['PG_DSN'], $env['PG_USER'], $env['PG_PASS'], $env['BC_PG_SCHEMA']);

        }

        // Pass only scalar values (proc_open expects that)
        $env = array_filter($env, fn($v) => is_scalar($v));

        $pA = proc_open("$php $cmdA", $desc, $pa, __DIR__ . '/../../', $env);
        $pB = proc_open("$php $cmdB", $desc, $pb, __DIR__ . '/../../', $env);
        // stdin is unused -> close immediately so children do not wait for EOF
        if (isset($pa[0]) && is_resource($pa[0])) fclose($pa[0]);
        if (isset($pb[0]) && is_resource($pb[0])) fclose($pb[0]);
        $this->assertIsResource($pA);
        $this->assertIsResource($pB);

        // Non-blocking stdout/stderr read
        foreach ([$pa, $pb] as $pipes) {
            foreach ([1, 2] as $i) {
                if (is_resource($pipes[$i])) {
                    stream_set_blocking($pipes[$i], false);
                }
            }
        }

        $outA = $errA = $outB = $errB = '';
        $deadline = microtime(true) + 20; // safety limit ~20s

        do {
            // drain both process outputs
            if (is_resource($pa[1])) { $c = stream_get_contents($pa[1]); if ($c !== '' && $c !== false) { $outA .= $c; } }
            if (is_resource($pa[2])) { $c = stream_get_contents($pa[2]); if ($c !== '' && $c !== false) { $errA .= $c; } }
            if (is_resource($pb[1])) { $c = stream_get_contents($pb[1]); if ($c !== '' && $c !== false) { $outB .= $c; } }
            if (is_resource($pb[2])) { $c = stream_get_contents($pb[2]); if ($c !== '' && $c !== false) { $errB .= $c; } }

            $stA = proc_get_status($pA);
            $stB = proc_get_status($pB);
            if (!($stA && $stA['running']) && !($stB && $stB['running'])) {
                break;
            }
            usleep(100_000);
        } while (microtime(true) < $deadline);

        // close pipes before proc_close so exit codes are accurate
        foreach ([&$pa, &$pb] as &$pipes) {
            foreach ([0, 1, 2] as $i) {
                if (isset($pipes[$i]) && is_resource($pipes[$i])) {
                    fclose($pipes[$i]);
                }
            }
        }

        $codeA = is_resource($pA) ? proc_close($pA) : -1;
        $codeB = is_resource($pB) ? proc_close($pB) : -1;

        // If deadlock (99) did not occur, dump full STDOUT/STDERR into the failure
        if (($codeA !== 99) && ($codeB !== 99)) {
            $this->fail(
                "Expected one worker to exit with deadlock (99), got A={$codeA}, B={$codeB}\n".
                "---- A: STDOUT ----\n{$outA}\n".
                "---- A: STDERR ----\n{$errA}\n".
                "---- B: STDOUT ----\n{$outB}\n".
                "---- B: STDERR ----\n{$errB}\n"
            );
        }
    }
}
