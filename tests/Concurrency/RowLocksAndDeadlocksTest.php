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
        // modulární instalace (idempotent)
        DbHarness::ensureInstalled();

        // najdi “bezpečnou” tabulku s identity PK 'id' a updatovatelným sloupcem (jen přes Definitions)
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
            if ($sample === null) continue; // povinné FK apod. – přeskoč

            // vyber běžný updatovatelný sloupec z Definitions (≠ id, ≠ audit)
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

        // TX1: zamkni řádek
        $pdo1->beginTransaction();
        $pdo1->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE")->execute([':id'=>$id]);

        // TX2: pokus o update -> lock timeout
        $pdo2->beginTransaction();
        ConnFactory::setShortLockTimeout($pdo2, 1000);
        $thrown = null;
        try {
            $pdo2->prepare("UPDATE ".self::$table." SET ".self::$updCol." = ".self::$updCol." WHERE id=:id")
                 ->execute([':id'=>$id]);
            // Pokud by k timeoutu nedošlo, fail
            $this->fail('Expected lock wait timeout, but UPDATE succeeded');
        } catch (\Throwable $e) {
            $thrown = $e;
        }
        $this->assertNotNull($thrown, 'Lock wait timeout did not happen');
        // PG: chyba abortuje celou TX → resetni ji, jinak skončíš na 25P02
        if ($pdo2->inTransaction()) {
            try { $pdo2->rollBack(); } catch (\Throwable $ignore) {}
        }
        $pdo2->beginTransaction();

        // uvolni zámek a zkus znovu
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
        // NOWAIT -> okamžitá chyba
        $err = null;
        try {
            $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE NOWAIT")->execute([':id'=>$id]);
            $this->fail('NOWAIT should have failed on locked row');
        } catch (\Throwable $e) { $err = $e; }
        $this->assertNotNull($err, 'NOWAIT did not raise');

        // PG: NOWAIT chyba abortuje transakci → začni čistou TX pro SKIP LOCKED
        if ($pdo2->inTransaction()) {
            try { $pdo2->rollBack(); } catch (\Throwable $ignore) {}
        }
        $pdo2->beginTransaction();

        // --- SKIP LOCKED / kompatibilní větev ---
        // Cíl: neblokovat a nevrátit zamknutý řádek.
        // 1) Zkusíme nativní SKIP LOCKED (PG, MySQL 8+). Pokud MariaDB hlásí syntaxi, přejdeme na fallback.
        $rows = null;

        try {
            $stmt = $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE SKIP LOCKED");
            $stmt->execute([':id'=>$id]);
            $rows = $stmt->fetchAll();
        } catch (\PDOException $e) {
            $sqlstate = (string)($e->errorInfo[0] ?? '');
            $errno    = (int)   ($e->errorInfo[1] ?? 0);
            $msg      = $e->getMessage();

            // MariaDB bez SKIP LOCKED: syntax error (1064/42000) → použij NOWAIT jako emulaci "skip".
            $unsupported = ($errno === 1064)            // SQL syntax error
            || ($errno === 1235)            // not supported yet
            || ($sqlstate === '42000')      // syntax error or access violation
            || ($sqlstate === 'HY000' && stripos($msg, 'not supported') !== false)
            || stripos($msg, 'SKIP LOCKED') !== false;

            if (!$unsupported) {
                throw $e; // jiná chyba, nemaskovat
            }

            // 2) Fallback: FOR UPDATE NOWAIT (neblokuje). Je-li řádek zamknutý, hned vyhodí výjimku → interpretujeme jako "nic k vyzvednutí".
            try {
                $stmt = $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE NOWAIT");
                $stmt->execute([':id'=>$id]);
                $rows = $stmt->fetchAll(); // kdyby náhodou nebyl zamknutý, vrátí řádky
            } catch (\PDOException $_) {
                $rows = []; // zamknuté → emulovaný "skip"
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

        $php = escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d error_reporting=32767';
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

        // Základ: celé prostředí rodiče (včetně proměnných z phpunit.xml)
        $env = $_ENV;
        $env['BC_DB'] = $norm;
        // Child procesy NESMÍ znovu instalovat bc_compat → vyhne se „tuple concurrently updated“
        $env['BC_SKIP_COMPAT'] = '1';
        // doplň PATH/HOME i když $_ENV je prázdné
        if (!isset($env['PATH']) || $env['PATH'] === '') { $env['PATH'] = getenv('PATH') ?: ''; }
        if (!isset($env['HOME']) || $env['HOME'] === '') { $env['HOME'] = getenv('HOME') ?: ''; }

        // Harden DSN podle cílového backendu (uvnitř Docker sítě MUSÍ být host=service)
        if ($norm === 'pg') {
            // když není PG_DSN, nebo ukazuje na localhost/127.0.0.1, přepiš na service "postgres"
            $pgDsn = $env['PG_DSN'] ?? (getenv('PG_DSN') ?: '');
            if ($pgDsn === '' || preg_match('~host\s*=\s*(127\.0\.0\.1|localhost)~i', $pgDsn)) {
                $db   = $env['PGDATABASE'] ?? (getenv('PGDATABASE') ?: 'test');
                $port = $env['PGPORT']     ?? (getenv('PGPORT') ?: '5432');
                $env['PG_DSN'] = "pgsql:host=postgres;port={$port};dbname={$db}";
            }
            // zajisti uživatele/heslo/schema i když nejsou v $_ENV
            $env['PG_USER']      = $env['PG_USER']      ?? (getenv('PG_USER')      ?: 'postgres');
            $env['PG_PASS']      = $env['PG_PASS']      ?? (getenv('PG_PASS')      ?: 'postgres');
            $env['BC_PG_SCHEMA'] = $env['BC_PG_SCHEMA'] ?? (getenv('BC_PG_SCHEMA') ?: 'public');

            // pokud není DSN, nebo míří na localhost, přepiš na service jméno
            $pgDsn = $env['PG_DSN'] ?? (getenv('PG_DSN') ?: '');
            if ($pgDsn === '' || preg_match('~host\s*=\s*(127\.0\.0\.1|localhost)~i', $pgDsn)) {
                $db   = $env['PGDATABASE'] ?? (getenv('PGDATABASE') ?: 'test');
                $port = $env['PGPORT']     ?? (getenv('PGPORT')     ?: '5432');
                $env['PG_DSN'] = "pgsql:host=postgres;port={$port};dbname={$db}";
            }

            // zamez ambiguitě – odstřihni MySQL proměnné
            unset($env['MYSQL_DSN'], $env['MYSQL_USER'], $env['MYSQL_PASS']);

        } else {
            // MySQL/MariaDB varianta – stejné pravidlo
            // zajisti uživatele/heslo i když nejsou v $_ENV
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

        // Předej jen skalarni hodnoty (proc_open totéž očekává)
        $env = array_filter($env, fn($v) => is_scalar($v));

        $pA = proc_open("$php $cmdA", $desc, $pa, __DIR__ . '/../../', $env);
        $pB = proc_open("$php $cmdB", $desc, $pb, __DIR__ . '/../../', $env);
        // stdin nebudeme nikdy používat → zavři hned, ať děti zbytečně nečekají na EOF
        if (isset($pa[0]) && is_resource($pa[0])) fclose($pa[0]);
        if (isset($pb[0]) && is_resource($pb[0])) fclose($pb[0]);
        $this->assertIsResource($pA);
        $this->assertIsResource($pB);

        // Neblokující čtení stdout/stderr
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
            // drénuj výstupy obou procesů
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

        // nejdřív zavři roury, ať proc_close vrátí korektní exit kód
        foreach ([&$pa, &$pb] as &$pipes) {
            foreach ([0, 1, 2] as $i) {
                if (isset($pipes[$i]) && is_resource($pipes[$i])) {
                    fclose($pipes[$i]);
                }
            }
        }

        $codeA = is_resource($pA) ? proc_close($pA) : -1;
        $codeB = is_resource($pB) ? proc_close($pB) : -1;

        // Pokud se deadlock (99) neobjevil, vynes kompletní STDOUT/STDERR do failu
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
