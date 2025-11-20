<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Umbrella;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Installer;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Util\DbUtil;

final class InstallerTest extends TestCase
{
    public function test_registry_created_and_upsert(): void
    {
        $ins = new Installer(DbUtil::db(), DbUtil::dialect());
        $ins->ensureRegistry();

        // fake module (no-op)
        $m = new class implements ModuleInterface {
            public function name(): string { return 'table-__fake'; }
            public function table(): string { return '__fake'; }
            public function version(): string { return '1.0.0'; }
            public function dialects(): array { return ['mysql','postgres']; }
            public function dependencies(): array { return []; }
            public function install(Database $db, SqlDialect $d): void { /* noop */ }
            public function upgrade(Database $db, SqlDialect $d, string $from): void { /* noop */ }
            public function uninstall(Database $db, SqlDialect $d): void { /* noop */ }
            public static function contractView(): string { return 'vw___fake'; }
            public function status(Database $db, SqlDialect $d): array { return ['table'=>true,'view'=>true,'missing_idx'=>[],'missing_fk'=>[],'version'=>'1.0.0']; }
            public function info(): array { return ['t'=>'__fake','v'=>'1.0.0']; }
        };

        $ins->installOrUpgrade($m);
        $ver = DbUtil::db()->fetchValue("SELECT version FROM _schema_registry WHERE module_name = :n", [':n'=>$m->name()]);
        $this->assertSame('1.0.0', $ver);

        // simulate upgrade
        $m2 = new class($m) implements ModuleInterface {
            public function __construct(private $base) {}
            public function name(): string { return $this->base->name(); }
            public function table(): string { return '__fake'; }
            public function version(): string { return '1.1.0'; }
            public function dialects(): array { return ['mysql','postgres']; }
            public function dependencies(): array { return []; }
            public function install(Database $db, SqlDialect $d): void {}
            public function upgrade(Database $db, SqlDialect $d, string $from): void { /* noop */ }
            public function uninstall(Database $db, SqlDialect $d): void { /* noop */ }
            public static function contractView(): string { return 'vw___fake'; }
            public function status(Database $db, SqlDialect $d): array { return ['table'=>true,'view'=>true,'missing_idx'=>[],'missing_fk'=>[],'version'=>'1.1.0']; }
            public function info(): array { return ['t'=>'__fake','v'=>'1.1.0']; }
        };

        $ins->installOrUpgrade($m2);
        $ver2 = DbUtil::db()->fetchValue("SELECT version FROM _schema_registry WHERE module_name = :n", [':n'=>$m2->name()]);
        $this->assertSame('1.1.0', $ver2);
        
    }

    public function test_toposort_cycle_detected(): void
    {
        $d = DbUtil::dialect();
        $db = DbUtil::db();

        $A = new class($db,$d) implements ModuleInterface {
            public function __construct(private Database $db, private SqlDialect $d) {}
            public function name(): string { return 'table-A'; }
            public function table(): string { return 'A'; }
            public function version(): string { return '1.0.0'; }
            public function dialects(): array { return ['mysql','postgres']; }
            public function dependencies(): array { return ['table-B']; }
            public function install(Database $db, SqlDialect $d): void {}
            public function upgrade(Database $db, SqlDialect $d, string $from): void {}
            public function uninstall(Database $db, SqlDialect $d): void { /* noop */ }
            public static function contractView(): string { return 'vw_A'; }
            public function status(Database $db, SqlDialect $d): array { return ['table'=>true,'view'=>true]; }
            public function info(): array { return []; }
        };
        $B = new class($db,$d) implements ModuleInterface {
            public function __construct(private Database $db, private SqlDialect $d) {}
            public function name(): string { return 'table-B'; }
            public function table(): string { return 'B'; }
            public function version(): string { return '1.0.0'; }
            public function dialects(): array { return ['mysql','postgres']; }
            public function dependencies(): array { return ['table-C']; }
            public function install(Database $db, SqlDialect $d): void {}
            public function upgrade(Database $db, SqlDialect $d, string $from): void {}
            public function uninstall(Database $db, SqlDialect $d): void { /* noop */ }
            public static function contractView(): string { return 'vw_B'; }
            public function status(Database $db, SqlDialect $d): array { return ['table'=>true,'view'=>true]; }
            public function info(): array { return []; }
        };
        $C = new class($db,$d) implements ModuleInterface {
            public function __construct(private Database $db, private SqlDialect $d) {}
            public function name(): string { return 'table-C'; }
            public function table(): string { return 'C'; }
            public function version(): string { return '1.0.0'; }
            public function dialects(): array { return ['mysql','postgres']; }
            public function dependencies(): array { return ['table-A']; } // cycle
            public function install(Database $db, SqlDialect $d): void {}
            public function upgrade(Database $db, SqlDialect $d, string $from): void {}
            public function uninstall(Database $db, SqlDialect $d): void { /* noop */ }
            public static function contractView(): string { return 'vw_C'; }
            public function status(Database $db, SqlDialect $d): array { return ['table'=>true,'view'=>true]; }
            public function info(): array { return []; }
        };

        $ins = new Installer($db, $d);
        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessageMatches('/cycle/i');
        $ins->installOrUpgradeAll([$A,$B,$C]);
    }
}
