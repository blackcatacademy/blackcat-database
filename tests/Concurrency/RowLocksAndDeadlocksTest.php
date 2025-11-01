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

        // SKIP LOCKED -> vrátí 0 řádků, neblokuje
        $stmt = $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE SKIP LOCKED");
        $stmt->execute([':id'=>$id]);
        $rows = $stmt->fetchAll();
        $this->assertIsArray($rows);
        $this->assertCount(0, $rows, 'SKIP LOCKED should skip locked row');

        $pdo1->commit();
        $pdo2->commit();
    }

    public function test_deadlock_detection(): void
    {
        $this->assertNotNull(self::$table);
        $pdo1 = ConnFactory::newPdo();
        $pdo2 = ConnFactory::newPdo();

        $idA = $this->insertRow($pdo1);
        $idB = $this->insertRow($pdo1);

        $pdo1->beginTransaction();
        $pdo2->beginTransaction();

        // TX1 zamkne A, TX2 zamkne B
        $pdo1->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE")->execute([':id'=>$idA]);
        $pdo2->prepare("SELECT id FROM ".self::$table." WHERE id=:id FOR UPDATE")->execute([':id'=>$idB]);

        // TX1 pokusí update B (blokuje se na TX2)
        $stmt1 = $pdo1->prepare("UPDATE ".self::$table." SET ".self::$updCol." = ".self::$updCol." WHERE id=:id");
        try { $stmt1->execute([':id'=>$idB]); } catch (\Throwable $ignore) {}

        // TX2 pokusí update A -> vznikne deadlock, jedna transakce padne
        $stmt2 = $pdo2->prepare("UPDATE ".self::$table." SET ".self::$updCol." = ".self::$updCol." WHERE id=:id");

        $deadlock = false;
        try {
            $stmt2->execute([':id'=>$idA]);
        } catch (\Throwable $e) {
            $deadlock = true;
        }

        $this->assertTrue($deadlock, 'Expected a deadlock to be detected by the DB');

        // cleanup – jedna TX bude zrušená, druhou dočistíme
        foreach ([$pdo1,$pdo2] as $pdo) {
            try { $pdo->rollBack(); } catch (\Throwable $ignore) {}
        }
    }
}
