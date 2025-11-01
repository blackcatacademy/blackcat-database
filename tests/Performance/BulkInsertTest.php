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
                    $defs = "BlackCat\\Database\\Packages\\{$m[1]}\\Definitions";
                    $uniqueKeys = $defs::uniqueKeys();
                    $isIdentity = $defs::isIdentityPk();

                    // zplošti seznam unikátních sloupců (i pro composite unikáty)
                    $uniqueCols = [];
                    foreach ($uniqueKeys as $uk) {
                        foreach ($uk as $col) {
                            $uniqueCols[$col] = true;
                        }
                    }
                    // Přidej i primární klíč, pokud NENÍ identity (natural PK je taky unikát)
                    $pkCol = $defs::pk();
                    if (!$isIdentity && $pkCol) { $uniqueCols[$pkCol] = true; }
                    break;
                }
            }
        }
        if (!$repo) $this->markTestSkipped('repo not found');

        [$sample] = RowFactory::makeSample($table);
        $rows = [];
        $N = 10000; // BC_STRESS=1 => schválně velké

        for ($i = 0; $i < $N; $i++) {
            $row = $sample;

            // Pokud je identity PK, nenech posílat "id" – přenech to DB
            if ($isIdentity) {
                unset($row['id']);
            }

            // Z unikátních sloupců vynecháme ty „enum-like“, které by porušily CHECK (typicky 'type', případně 'status' apod.)
            $skipForEnumLike = ['type','status','state','level'];

            $toVary = [];
            foreach (array_keys($uniqueCols) as $col) {
                if (in_array($col, $skipForEnumLike, true)) continue;
                $toVary[] = $col;
            }
            // Kdyby náhodou všechny byly enum-like (velmi nepravděpodobné), spadneme na původní chování:
            if (!$toVary) { $toVary = array_keys($uniqueCols); }

            foreach ($toVary as $col) {
                if (!array_key_exists($col, $row)) continue;

                $val = $row[$col];
                if (is_string($val)) {
                    $row[$col] = $val . '-' . $i;
                } elseif (is_int($val)) {
                    $row[$col] = $val + $i + 1;
                } else {
                    $row[$col] = (string)$val . '-' . $i;
                }
            }

            $rows[] = $row;
        }

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
