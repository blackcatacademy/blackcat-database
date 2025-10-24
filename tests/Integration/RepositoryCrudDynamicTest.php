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
    /** @var array<string,string> FQN repozitářů dle tabulky */
    private static array $repos = [];

    public static function setUpBeforeClass(): void
    {
        DbHarness::ensureInstalled();
        // najdi Repository třídy balíčků (BlackCat\Database\Packages\Xxx\Repository)
        $root = realpath(__DIR__ . '/../../packages');
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if ($f->isFile() && preg_match('~/packages/([^/]+)/src/Repository\.php$~', $f->getPathname(), $m)) {
                $pkg = $m[1];
                $pascal = implode('', array_map(fn($x)=>ucfirst($x), preg_split('/[_-]/', $pkg)));
                $class = "BlackCat\\Database\\Packages\\{$pascal}\\Repository";
                if (!class_exists($class)) require_once $f->getPathname();

                $defs = "BlackCat\\Database\\Packages\\{$pascal}\\Definitions";
                if (!class_exists($defs)) {
                    $mod = "BlackCat\\Database\\Packages\\{$pascal}\\{$pascal}Module";
                    if (class_exists($mod)) {
                        $ref = new \ReflectionClass($mod);
                        $p = dirname($ref->getFileName()) . '/Definitions.php';
                        if (is_file($p)) require_once $p;
                    }
                }
                if (class_exists($class) && class_exists($defs)) {
                    /** @var class-string $defs */
                    $table = $defs::table();
                    self::$repos[$table] = $class;
                }
            }
        }
    }

    public static function safeTablesProvider(): array
    {
        $out = [];
        foreach (self::$repos as $table => $repoFqn) {
            [$row] = RowFactory::makeSample($table);
            if ($row !== null) { $out[] = [$table, $repoFqn]; }
        }
        return $out ?: [['app_settings', self::$repos['app_settings'] ?? '']];
    }

    /**
     * @dataProvider safeTablesProvider
     */
    public function test_crud_upsert_lock_smoke(string $table, string $repoFqn): void
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

            // FIND (pokud tabulka má pk 'id', zkusíme jej přečíst)
            $pk = 'id';
            $id = $db->fetchOne("SELECT $pk FROM $table ORDER BY $pk DESC LIMIT 1");
            if ($id !== null) {
                $found = $repo->findById((int)$id);
                $this->assertIsArray($found);
            }

            // UPDATE
            if ($id !== null && $updatable) {
                $k = $updatable[0];
                $newVal = is_numeric($row[$k] ?? null) ? ($row[$k]+1) : (($row[$k] ?? '') . 'u');
                $aff = $repo->updateById((int)$id, [$k=>$newVal]);
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
                $rowLocked = $repo->lockById((int)$id);
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
