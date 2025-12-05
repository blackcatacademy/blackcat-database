<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Umbrella;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Installer;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Database\Tests\Util\DbUtil;
use BlackCat\Core\Database;

final class InstallerMissingDependencyTest extends TestCase
{
    public function test_install_refuses_when_dependency_missing(): void
    {
        $db = DbUtil::db();
        $dial = DbUtil::dialect();
        $ins = new Installer($db, $dial);
        $ins->ensureRegistry();

        $m = new class implements ModuleInterface {
            public function name(): string { return 'table-child'; }
            public function table(): string { return 'child'; }
            public function version(): string { return '1.0.0'; }
            public function dialects(): array { return ['mysql','postgres']; }
            public function dependencies(): array { return ['table-parent']; } // parent is not registered
            public function install(Database $db, SqlDialect $d): void {}
            public function upgrade(Database $db, SqlDialect $d, string $from): void {}
            public function uninstall(Database $db, SqlDialect $d): void {}
            public static function contractView(): string { return 'vw_child'; }
            public function status(Database $db, SqlDialect $d): array {
                return ['table'=>false,'view'=>false];
            }
            public function info(): array { return ['t'=>'child']; }
        };

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessageMatches('/missing dependencies/i');
        $ins->installOrUpgrade($m);
    }
}
