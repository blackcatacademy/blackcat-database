<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Tests\Support\DbHarness;

final class InstallAndStatusTest extends TestCase
{
    private static array $mods;

    public static function setUpBeforeClass(): void
    {
        self::$mods = DbHarness::ensureInstalled();
    }

    public function test_all_modules_installed_and_status_ok(): void
    {
        [$dial] = DbHarness::dialect();
        $db = Database::getInstance();
        $fail = [];

        foreach (self::$mods as $m) {
            $st = $m->status($db, $dial);
            $ok = !empty($st['table']) && !empty($st['view'])
                && empty($st['missing_idx'] ?? []) && empty($st['missing_fk'] ?? [])
                && ($st['version'] ?? '') === $m->version();

            if (!$ok) {
                $fail[] = [$m->name(), $st];
            }
        }
        $this->assertSame([], $fail, "Some modules failed status");
    }

    public function test_uninstall_removes_only_view(): void
    {
        // Pro rychlost testujeme jen 3 náhodné moduly
        $pick = array_values(self::$mods);
        shuffle($pick);
        $pick = array_slice($pick, 0, min(3, count($pick)));

        [$dial] = DbHarness::dialect();
        $db = Database::getInstance();

        foreach ($pick as $m) {
            $table = $m->table();
            $view  = (method_exists($m,'contractView') ? $m::contractView() : $table);
            $m->uninstall($db, $dial);

            // view pryč, tabulka zůstává
            $tableOk = (int)$db->fetchOne(
                $dial->isMysql()
                    ? "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t"
                    : "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name=:t",
                [':t'=>$table]
            ) === 1;
            $viewGone = (int)$db->fetchOne(
                $dial->isMysql()
                    ? "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :v"
                    : "SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_views WHERE viewname = :v) THEN 1 ELSE 0 END",
                [':v'=>$view]
            ) === 0;

            $this->assertTrue($tableOk, "Table missing after uninstall: $table");
            $this->assertTrue($viewGone, "View still present after uninstall: $view");

            // reinstal zpět
            $m->install($db, $dial);
        }
    }
}
