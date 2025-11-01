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

        // najdi první balíček s versionColumn() a odvoď repo přes DbHarness
        foreach (glob(__DIR__ . '/../../packages/*/src/Definitions.php') as $df) {
            require_once $df;
            if (!preg_match('~[\\\\/]packages[\\\\/]([A-Za-z0-9_]+)[\\\\/]src[\\\\/]Definitions\.php$~i', $df, $m)) continue;
            $ns = $m[1];
            $defs = "BlackCat\\Database\\Packages\\{$ns}\\Definitions";
            if (!class_exists($defs)) continue;

            $ver = $defs::versionColumn();
            if (!$ver) continue;

            $table = $defs::table();
            $repoFqn = self::resolveRepoFqn($ns, $defs);
            if (!$repoFqn) continue;

            [$row] = RowFactory::makeSample($table);
            if ($row === null) continue;

            // najdi updatovatelný sloupec z Definitions::columns() (≠ PK, ≠ version, ≠ audit)
            $bad    = [$defs::pk(), (string)$ver, 'created_at', 'updated_at', 'deleted_at'];
            $updCol = null;
            foreach ((array)$defs::columns() as $name) {
                $name = (string)$name;
                if ($name === '' || in_array($name, $bad, true)) continue;
                $updCol = $name; break;
            }
            if (!$updCol) continue;

            self::$table = $table;
            self::$repoFqn = get_class(DbHarness::repoFor($table));
            self::$verCol = $ver;
            self::$updCol = $updCol;
            break;
        }
        if (!self::$table) {
            self::markTestSkipped('No table with versionColumn() found.');
        }
    }

    private static function resolveRepoFqn(string $pkgPascal, string $defsFqn): ?string
    {
        try { $table = $defsFqn::table(); } catch (\Throwable) { return null; }
        $entityPascal = self::toPascalCase(self::singularize($table));
        $cand = "BlackCat\\Database\\Packages\\{$pkgPascal}\\Repository\\{$entityPascal}Repository";
        if (class_exists($cand)) { return $cand; }

        $dir = __DIR__ . "/../../packages/{$pkgPascal}/src/Repository";
        foreach (glob($dir . '/*Repository.php') ?: [] as $file) {
            $base = basename($file, '.php');
            $fqn  = "BlackCat\\Database\\Packages\\{$pkgPascal}\\Repository\\{$base}";
            if (class_exists($fqn)) { return $fqn; }
            require_once $file;
            if (class_exists($fqn)) { return $fqn; }
        }
        return null;
    }

    private static function singularize(string $word): string
    {
        if (preg_match('~ies$~i', $word))   return preg_replace('~ies$~i', 'y', $word);
        if (preg_match('~sses$~i', $word))  return preg_replace('~es$~i',  '',  $word);
        if (preg_match('~s$~i', $word) && !preg_match('~(news|status)$~i', $word)) {
            return substr($word, 0, -1);
        }
        return $word;
    }

    private static function toPascalCase(string $snakeOrKebab): string
    {
        $parts = preg_split('~[_\-]+~', $snakeOrKebab) ?: [];
        $parts = array_map(fn($p) => $p === '' ? $p : (mb_strtoupper(mb_substr($p,0,1)).mb_strtolower(mb_substr($p,1))), $parts);
        return implode('', $parts);
    }

    public function test_optimistic_locking_succeeds_then_fails_with_stale_version(): void
    {
        $db = Database::getInstance();
        $repo = new (self::$repoFqn)($db);

        DbHarness::begin();
        try {
            // vlož řádek (přes čisté SQL – Repository insert by taky šel)
            $ins   = RowFactory::insertSample(self::$table);
            $pkCol = DbHarness::primaryKey(self::$table);
            $id    = $ins['pk'];
            $this->assertNotEmpty($id);

            $ver = (int)($db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE {$pkCol} = :id", [':id'=>$id]) ?? 0);

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
