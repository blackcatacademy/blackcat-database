<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Contract;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\AssertSql;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use FilesystemIterator;

final class ContractViewSmokeTest extends TestCase
{
    public function test_select_from_each_contract_view(): void
    {
        DbHarness::ensureInstalled();
        $root = realpath(__DIR__ . '/../../packages') ?: (__DIR__ . '/../../packages');
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
        $views = [];
        foreach ($it as $f) {
            if ($f->isFile() && preg_match('~/packages/([^/]+)/schema/040_(?:views|view_contract)\.(mysql|postgres)\.sql$~', $f->getPathname())) {
                // determine view name via Definitions::contractView()
                $pkg = basename(dirname(dirname($f->getPathname()))); // packages/<pkg>/schema/...
                $parts = preg_split('/[_-]/', $pkg) ?: [];
                $pascal = implode('', array_map('ucfirst', $parts));
                $defs = "BlackCat\\Database\\Packages\\{$pascal}\\Definitions";
                if (class_exists($defs) && method_exists($defs,'contractView')) {
                    $views[$pkg] = $defs::contractView();
                }
            }
        }
        $this->assertNotEmpty($views);

        $db = Database::getInstance();
        foreach ($views as $pkg=>$view) {
            AssertSql::viewExists($view);
            $rows = $db->fetchAll("SELECT * FROM $view ORDER BY 1 LIMIT 1");
            $this->assertIsArray($rows);
        }
    }
}
