<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Concurrency;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;

/**
 * Testuje optimistic locking přes Repository::updateById()
 * pro první tabulku, která má versionColumn().
 */
final class OptimisticLockingRepositoryTest extends TestCase
{
    private static ?string $table = null;
    private static ?string $repoFqn = null;
    private static ?string $verCol = null;
    private static ?string $updCol = null;

    public static function setUpBeforeClass(): void
    {
        DbHarness::ensureInstalled();

        // najdi první balíček s versionColumn()
        foreach (glob(__DIR__ . '/../../packages/*/src/Definitions.php') as $df) {
            require_once $df;
            if (!preg_match('~Packages/([A-Za-z0-9_]+)/src/Definitions\.php$~', $df, $m)) continue;
            $ns = $m[1];
            $defs = "BlackCat\\Database\\Packages\\{$ns}\\Definitions";
            $repo = "BlackCat\\Database\\Packages\\{$ns}\\Repository";
            if (!class_exists($defs) || !class_exists($repo)) continue;

            $ver = $defs::versionColumn();
            if (!$ver) continue;

            $table = $defs::table();
            [$row, $upd] = RowFactory::makeSample($table);
            if ($row === null) continue;

            // najdi updatovatelný sloupec odlišný od version
            $updCol = null;
            foreach (DbHarness::columns($table) as $c) {
                if ($c['name'] === 'id' || $c['is_identity']) continue;
                if ($c['name'] === $ver) continue;
                $updCol = $c['name']; break;
            }
            if (!$updCol) continue;

            self::$table = $table;
            self::$repoFqn = $repo;
            self::$verCol = $ver;
            self::$updCol = $updCol;
            break;
        }
        if (!self::$table) {
            self::markTestSkipped('No table with versionColumn() found.');
        }
    }

    public function test_optimistic_locking_succeeds_then_fails_with_stale_version(): void
    {
        $db = Database::getInstance();
        $repo = new (self::$repoFqn)($db);

        DbHarness::begin();
        try {
            // vlož řádek (přes čisté SQL – Repository insert by taky šel)
            [$row] = RowFactory::makeSample(self::$table);
            $cols = array_keys($row);
            $ph   = array_map(fn($c)=>":$c", $cols);
            $db->execute("INSERT INTO ".self::$table." (".implode(',', $cols).") VALUES (".implode(',', $ph).")",
                array_combine($ph, array_values($row)));

            $id = (int)$db->fetchOne("SELECT id FROM ".self::$table." ORDER BY id DESC LIMIT 1");
            $this->assertGreaterThan(0, $id);

            $ver = (int)($db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE id = :id", [':id'=>$id]) ?? 0);

            // 1) korektní update s očekávanou verzí
            $aff = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'x1' ]);
            $this->assertSame(1, $aff, 'First update (expected version) should succeed');

            // 2) pokus se starou verzí (stejná hodnota) => 0 řádků
            $aff2 = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'x2' ]);
            $this->assertSame(0, $aff2, 'Second update with stale version should affect 0 rows');

        } finally {
            DbHarness::rollback();
        }
    }
}
