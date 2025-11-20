<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Umbrella;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Tests\Util\DbUtil;
use BlackCat\Database\Installer;
use BlackCat\Database\SqlDialect;

final class ModulesContractTest extends TestCase
{
    private Installer $installer;

    public static function setUpBeforeClass(): void
    {
        DbUtil::wipeDatabase();
    }

    protected function setUp(): void
    {
        $this->installer = new Installer(DbUtil::db(), DbUtil::dialect());
        $this->installer->ensureRegistry();
    }

    public function test_install_idempotent_status_uninstall_reinstall(): void
    {
        // clean DB to guarantee idempotency
        DbUtil::wipeDatabase();

        $db  = DbUtil::db();
        $d   = DbUtil::dialect();
        $ins = new Installer($db, $d);

        $mods = DbUtil::discoverModules();
        $this->assertNotEmpty($mods, 'No modules discovered under packages/');

        // 1) full install in topological order + idempotent second run
        $ins->installOrUpgradeAll($mods);
        $ins->installOrUpgradeAll($mods);

        // 2) per-module status checks
        foreach ($mods as $m) {
            $st = $m->status($db, $d);
            $this->assertTrue(!empty($st['table']), $m->name().' table missing');
            $this->assertTrue(!empty($st['view']),  $m->name().' view missing');
            $this->assertSame($m->version(), $st['version'] ?? null, $m->name().' version mismatch');
            $this->assertSame([], $st['missing_idx'] ?? [], $m->name().' index missing');
            $this->assertSame([], $st['missing_fk']  ?? [], $m->name().' fk missing');
        }

        // 3) uninstall everything (only views are dropped)
        foreach ($mods as $m) {
            $m->uninstall($db, $d);
        }
        foreach ($mods as $m) {
            $st2 = $m->status($db, $d);
            $this->assertTrue(!empty($st2['table']), $m->name().' table vanished after uninstall');
            $this->assertTrue(empty($st2['view']),   $m->name().' view still present after uninstall');
        }

        // 4) reinstall the whole set
        $ins->installOrUpgradeAll($mods);
        $this->assertTrue(true);
    }
}
