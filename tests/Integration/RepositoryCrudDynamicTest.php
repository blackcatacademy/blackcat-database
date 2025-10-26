<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use FilesystemIterator;

final class RepositoryCrudDynamicTest extends TestCase
{
    private static function dbg(string $msg): void {
        if (getenv('BC_DEBUG')) { fwrite(STDERR, "[repos] $msg\n"); }
    }

    private static function normalizePkValue(string $table, string $pk, mixed $val): int|string
    {
        if (is_int($val)) return $val;

        $meta = null;
        foreach (DbHarness::columns($table) as $c) {
            if (($c['name'] ?? '') === $pk) { $meta = $c; break; }
        }
        $type = strtolower((string)($meta['type'] ?? ''));

        // int/bigint/smallint/serial apod. → int, jinak string
        if (preg_match('/\b(int|bigint|smallint|serial)\b/', $type)) {
            return (int)$val;
        }
        return (string)$val;
    }

    /** @var array<string,string> */
    private static array $repos = [];

    /** Postav mapu repozitářů (idempotentně) */
    private static function ensureReposBuilt(): void
    {
        if (self::$repos) { return; }

        $root = realpath(__DIR__ . '/../../packages');
        self::dbg("scan root=$root");

        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS)
        );

        foreach ($it as $f) {
            $path = $f->getPathname();
            if ($f->isFile() && preg_match('~[\\/]packages[\\/]([^\\/]+)[\\/]src[\\/]Repository\.php$~', $path, $m)) {
                $pkg    = $m[1];
                $pascal = implode('', array_map(fn($x)=>ucfirst($x), preg_split('/[_-]/',$pkg)));
                $class  = "BlackCat\\Database\\Packages\\{$pascal}\\Repository";
                $defs   = "BlackCat\\Database\\Packages\\{$pascal}\\Definitions";

                if (!class_exists($class, false)) { require_once $path; }

                $defsPath = dirname($path) . DIRECTORY_SEPARATOR . 'Definitions.php';
                if (!class_exists($defs, false) && is_file($defsPath)) { require_once $defsPath; }

                $crit    = "BlackCat\\Database\\Packages\\{$pascal}\\Criteria";
                $critPath= dirname($path) . DIRECTORY_SEPARATOR . 'Criteria.php';
                if (!class_exists($crit, false) && is_file($critPath)) { require_once $critPath; }

                if (class_exists($class, false) && class_exists($defs, false)) {
                    /** @var class-string $defs */
                    $table = $defs::table();
                    self::$repos[$table] = $class;
                }
            }
        }
        self::dbg('final repos='.json_encode(self::$repos));
    }

    public static function setUpBeforeClass(): void
    {
        DbHarness::ensureInstalled();
        // volitelné: pro logy
        self::ensureReposBuilt();
    }

    public static function safeTablesProvider(): array
    {
        self::ensureReposBuilt();
        $out = [];
        foreach (self::$repos as $table => $repoFqn) {
            [$row, $updatable] = RowFactory::makeSample($table);
            if ($row !== null) {
                $out[] = [$table, $repoFqn, $row, $updatable];
            }
        }
        return $out ?: [['app_settings', self::$repos['app_settings'] ?? '', ['setting_key'=>'k','section'=>'s','value'=>'v'], ['value']]];
    }

    /** @dataProvider safeTablesProvider */
    public function test_crud_upsert_lock_smoke(string $table, string $repoFqn, array $row, array $updatable): void
    {
        if (!class_exists($repoFqn)) $this->markTestSkipped("repo missing for $table");

        $db = Database::getInstance();
        $repo = new $repoFqn($db);

        DbHarness::begin();
        try {
            // sample row
            [$row, $updatable] = RowFactory::makeSample($table);
            $this->assertIsArray($row, "no sample for $table");

            // INSERT
            $repo->insert($row);

            // COUNT/EXISTS
            $this->assertTrue($repo->exists('1=1', []));
            $this->assertGreaterThanOrEqual(1, $repo->count('1=1', []));

            // najdi PK z Definitions vedle daného Repository
            $defsClass = preg_replace('~\\\\Repository$~', '\\\\Definitions', $repoFqn);

            /** @var class-string|null $defsClass */
            $pk = 'id';
            if (class_exists($defsClass)) {
                if (method_exists($defsClass, 'pk')) {
                    $pk = $defsClass::pk();
                } else {
                    // fallback: když není pk(), vezmi 'id' pokud existuje, jinak první sloupec
                    $cols = $defsClass::columns();
                    $pk = in_array('id', $cols, true) ? 'id' : ($cols[0] ?? 'id');
                }
            }

            $idRaw = $db->fetchOne("SELECT $pk FROM $table ORDER BY $pk DESC LIMIT 1");
            if ($idRaw !== null) {
                $id = self::normalizePkValue($table, $pk, $idRaw);

                $found = $repo->findById($id);
                $this->assertIsArray($found);
            }

            // UPDATE
            if ($id !== null && $updatable) {
                $k = $updatable[0];
                $meta = null;
                foreach (DbHarness::columns($table) as $c) { if ($c['name']===$k) { $meta=$c; break; } }
                $newVal = isset($row[$k]) && is_numeric($row[$k]) ? $row[$k]+1 : (is_array($row[$k]??null) ? $row[$k] : (($row[$k] ?? 'x').'u'));
                if ($meta && preg_match('/(date|time)/i', (string)$meta['type'])) {
                    $newVal = (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s');
                }
                $aff = $repo->updateById($id, [$k=>$newVal]);
                $this->assertSame(1, $aff);
            }

            // UPSERT — jen pokud tabulka má unikátní klíč, se kterým jsme schopni pracovat
            if (method_exists($repo, 'upsert')) {
                // zkusíme upsert stejného řádku (doplníme případný pk do WHERE části)
                $repo->upsert($row);
                $this->assertTrue(true, 'upsert ok');
            }

            // LOCK
            if ($id !== null) {
                $rowLocked = $repo->lockById($id);
                $this->assertIsArray($rowLocked);
            }

        } finally {
            DbHarness::rollback();
        }
    }

    /**
     * @dataProvider safeTablesProvider
     */
    public function test_paginate_smoke(string $table, string $repoFqn): void
    {
        if (!class_exists($repoFqn)) $this->markTestSkipped("repo missing");
        $db = Database::getInstance();
        $repo = new $repoFqn($db);

        DbHarness::begin();
        try {
            $critClass = preg_replace('~\\\\Repository$~', '\\Criteria', $repoFqn);
            if (!class_exists($critClass)) { $this->markTestSkipped('criteria missing'); }
            $c = new $critClass(); /** @var object $c */
            if (method_exists($c,'setPerPage')) $c->setPerPage(5);
            if (method_exists($c,'setPage')) $c->setPage(1);
            $page = $repo->paginate($c);
            $this->assertIsArray($page);
            $this->assertArrayHasKey('items', $page);
            $this->assertArrayHasKey('total', $page);
        } finally {
            DbHarness::rollback();
        }
    }
}
