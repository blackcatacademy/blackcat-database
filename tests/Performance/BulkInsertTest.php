<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Performance;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;

final class BulkInsertTest extends TestCase
{
    public function test_bulk_insert_on_safe_table(): void
    {
        if ((getenv('BC_STRESS') ?: '0') !== '1') {
            $this->markTestSkipped('BC_STRESS=1 to enable');
        }

        DbHarness::ensureInstalled();
        $db = Database::getInstance();

        // vyber bezpečnou tabulku – preferuj takovou s auto id a bez FK povinností
        $table = null;
        foreach (scandir(__DIR__ . '/../../packages') as $pkg) {
            if ($pkg === '.' || $pkg === '..') continue;
            $defs = "BlackCat\\Database\\Packages\\".implode('', array_map('ucfirst', preg_split('/[_-]/',$pkg)))."\\Definitions";
            if (!class_exists($defs)) continue;
            $t = $defs::table();
            [$row] = RowFactory::makeSample($t);
            if ($row !== null) { $table = $t; break; }
        }
        if (!$table) $this->markTestSkipped('no safe table');

        // repo FQN
        $pascal = implode('', array_map('ucfirst', preg_split('/[_-]/',$table)));
        // fallback: pokus o nalezení Repository přes filesystem
        $repo = null;
        foreach (glob(__DIR__."/../../packages/*/src/Repository.php") as $rf) {
            $code = file_get_contents($rf);
            if (preg_match('/namespace\s+BlackCat\\\\Database\\\\Packages\\\\([A-Za-z0-9_]+)/', $code, $m)) {
                $defs = "BlackCat\\Database\\Packages\\{$m[1]}\\Definitions";
                if (class_exists($defs) && $defs::table() === $table) {
                    $repoClass = "BlackCat\\Database\\Packages\\{$m[1]}\\Repository";
                    require_once $rf;
                    $repo = new $repoClass($db);
                    break;
                }
            }
        }
        if (!$repo) $this->markTestSkipped('repo not found');

        [$sample] = RowFactory::makeSample($table);
        $rows = [];
        $N = 10000; // v CI to může být moc – ale BC_STRESS=1 je explicitní
        for ($i=0;$i<$N;$i++) { $rows[] = $sample; }

        DbHarness::begin();
        try {
            $repo->insertMany($rows);
            $cnt = (int)$db->fetchOne("SELECT COUNT(*) FROM $table");
            $this->assertGreaterThanOrEqual($N, $cnt);
        } finally {
            DbHarness::rollback();
        }
    }
}
