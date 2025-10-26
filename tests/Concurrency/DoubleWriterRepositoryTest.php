<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Concurrency;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;
use BlackCat\Database\Tests\Support\ConnFactory;

/**
 * Dvě repo vrstvy (ve dvou procesech):
 *  - Locker:  tests/support/lock_row_repo.php  -> Repository::lockById()
 *  - Writer:  tento test -> Repository::updateById()
 *
 * Ověřuje:
 *  1) lock timeout během zápisu
 *  2) po uvolnění zámku update projde
 *  3) (pokud má tabulka version) – optimistic locking repo-vs-repo se stale verzí
 */
final class DoubleWriterRepositoryTest extends TestCase
{
    private static ?string $repoFqn = null;
    private static ?string $table   = null;
    private static ?string $updCol  = null;
    private static ?string $verCol  = null;

    public static function setUpBeforeClass(): void
    {
        DbHarness::ensureInstalled();

        // Najdi první balík, který má Repository a tabulku s PK=id a updatovatelným sloupcem
        foreach (glob(__DIR__ . '/../../packages/*/src/Definitions.php') as $df) {
            require_once $df;
            if (!preg_match('~[\\\\/]packages[\\\\/]([A-Za-z0-9_]+)[\\\\/]src[\\\\/]Definitions\.php$~i', $df, $m)) continue;
            $pkgPascal = $m[1];

            $defs = "BlackCat\\Database\\Packages\\{$pkgPascal}\\Definitions";
            $repo = "BlackCat\\Database\\Packages\\{$pkgPascal}\\Repository";
            if (!class_exists($defs) || !class_exists($repo)) continue;

            $table   = $defs::table();
            $verCol  = $defs::versionColumn();
            $columns = DbHarness::columns($table);
            $hasId   = false;
            foreach ($columns as $c) {
                if ($c['name'] === 'id' && $c['is_identity']) { $hasId = true; break; }
            }
            if (!$hasId) continue;

            // vyber nějaký běžný update sloupec ≠ id ≠ version
            $updCol = null;
            foreach ($columns as $c) {
                if ($c['name'] === 'id') continue;
                if ($verCol && $c['name'] === $verCol) continue;
                $updCol = $c['name']; break;
            }
            if (!$updCol) continue;

            self::$repoFqn = $repo;
            self::$table   = $table;
            self::$updCol  = $updCol;
            self::$verCol  = $verCol ?: null;
            break;
        }

        if (!self::$repoFqn) {
            self::markTestSkipped('No suitable Repository with identity PK found.');
        }
    }

    private function insertRowAndGetId(Database $db): int
    {
        [$row] = RowFactory::makeSample(self::$table);
        $cols = array_keys($row);
        $ph   = array_map(fn($c)=>":$c", $cols);
        $db->execute(
            "INSERT INTO ".self::$table." (".implode(',', $cols).") VALUES (".implode(',', $ph).")",
            array_combine($ph, array_values($row))
        );
        return (int)$db->fetchOne("SELECT id FROM ".self::$table." ORDER BY id DESC LIMIT 1");
    }

    public function test_repo_update_times_out_while_other_repo_holds_lock(): void
    {
        $db  = Database::getInstance();
        $pdo = $db->getPdo();

        $id = $this->insertRowAndGetId($db);
        $this->assertGreaterThan(0, $id);

        // Spusť locker proces (Repository::lockById) na N sekund
        $repoFqn  = self::$repoFqn;
        $seconds  = 5; // držet lock ~5s
        $cmd = sprintf(
            'php %s "%s" %d %d',
            escapeshellarg(__DIR__.'/../support/lock_row_repo.php'),
            $repoFqn,
            $id,
            $seconds
        );
        $desc = [['pipe','r'],['pipe','w'],['pipe','w']];
        $proc = proc_open($cmd, $desc, $pipes, __DIR__.'/../../'); // cwd = repo root (kvůli autoloadu)
        $this->assertIsResource($proc, 'Failed to start locker process');

        // Dej locker procesu čas nabrat FOR UPDATE lock
        usleep(300_000); // 300ms

        // writer – zkrať lock timeout a pokus se o update přes Repository
        ConnFactory::setShortLockTimeout($pdo, 1000);
        $repo = new $repoFqn($db);
        $thrown = null;
        try {
            // bez optimistic param – čistý zápis, který se má blokovat
            $repo->updateById($id, [ self::$updCol => 'x-lock' ]);
            $this->fail('Expected lock wait timeout, but update succeeded.');
        } catch (\Throwable $e) {
            $thrown = $e;
        }
        $this->assertNotNull($thrown, 'Lock wait timeout was not thrown.');

        // Počkej až locker proces skončí (uvolní lock)
        $status = proc_get_status($proc);
        while ($status && $status['running']) {
            usleep(100_000);
            $status = proc_get_status($proc);
        }
        foreach ($pipes as $p) { if (is_resource($p)) fclose($p); }
        if (is_resource($proc)) proc_close($proc);

        // Teď už update projde
        $aff = $repo->updateById($id, [ self::$updCol => 'x-after' ]);
        $this->assertSame(1, $aff, 'Update should succeed after lock released.');
    }

    public function test_repo_vs_repo_optimistic_locking_with_stale_version_if_supported(): void
    {
        if (!self::$verCol) {
            $this->markTestSkipped('Selected table has no version column.');
        }

        $db  = Database::getInstance();
        $pdo = $db->getPdo();

        $id = $this->insertRowAndGetId($db);
        $this->assertGreaterThan(0, $id);
        $ver = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE id=:id", [':id'=>$id]);

        // Locker proces drží lock přes Repository::lockById
        $repoFqn = self::$repoFqn;
        $cmd = sprintf(
            'php %s "%s" %d %d',
            escapeshellarg(__DIR__.'/../support/lock_row_repo.php'),
            $repoFqn,
            $id,
            3
        );
        $proc = proc_open($cmd, [['pipe','r'],['pipe','w'],['pipe','w']], $pipes, __DIR__.'/../../');
        $this->assertIsResource($proc);

        usleep(300_000); // 300ms na získání zámku

        // Writer zkrátí lock timeout a pokusí se o update s očekávanou verzí -> timeout (před uvolněním)
        ConnFactory::setShortLockTimeout($pdo, 1000);
        $repo = new $repoFqn($db);
        $caught = null;
        try {
            $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r1' ]);
            $this->fail('Expected lock wait timeout before lock release.');
        } catch (\Throwable $e) { $caught = $e; }
        $this->assertNotNull($caught);

        // Po uvolnění zámku proběhne první update -> verze ++
        $status = proc_get_status($proc);
        while ($status && $status['running']) { usleep(100_000); $status = proc_get_status($proc); }
        foreach ($pipes as $p) { if (is_resource($p)) fclose($p); }
        if (is_resource($proc)) proc_close($proc);

        $aff1 = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r2' ]);
        $this->assertSame(1, $aff1, 'First optimistic update should succeed.');

        // Druhý writer (stale version) – simuluj tak, že použijeme opět 'ver' (nezvýšený)
        $aff2 = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r3' ]);
        $this->assertSame(0, $aff2, 'Second optimistic update with stale version must affect 0 rows.');
    }
}
