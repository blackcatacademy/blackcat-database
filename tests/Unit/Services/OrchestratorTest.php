<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Orchestrator;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Runtime;
use BlackCat\Database\Registry;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Core\Database;
use Psr\Log\NullLogger;

final class OrchestratorTest extends TestCase
{
    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn'=>'sqlite::memory:','user'=>null,'pass'=>null,'options'=>[]], new NullLogger());
        }
    }

    public function testRunDryAndApply(): void
    {
        $db = Database::getInstance();
        $dialect = $db->isPg() ? SqlDialect::postgres : SqlDialect::mysql;
        $rt = new Runtime($db, $dialect, new NullLogger());
        $orc = new Orchestrator($rt);

        $orc->run(['CREATE TABLE IF NOT EXISTS x(a INT)'], true, ['op'=>'test']);

        $orc->run(['CREATE TABLE IF NOT EXISTS y(a INT)','INSERT INTO y(a) VALUES (1)'], false, ['op'=>'test']);
        $this->assertSame(1, (int)$db->fetchOne('SELECT COUNT(*) FROM y'));
    }

    public function testStatusAndInstallers(): void
    {
        $db = Database::getInstance();
        // Point installer to an empty schema dir (unit test — no real DDL)
        $oldSchemaDir = getenv('BC_SCHEMA_DIR') ?: null;
        $tmpSchema = sys_get_temp_dir() . '/bc-schema-empty';
        if (!is_dir($tmpSchema)) { @mkdir($tmpSchema, 0777, true); }
        putenv("BC_SCHEMA_DIR={$tmpSchema}");
        $_ENV['BC_SCHEMA_DIR'] = $tmpSchema;

        $dialect = $db->isPg() ? SqlDialect::postgres : SqlDialect::mysql;
        $inst = new \BlackCat\Database\Installer($db, $dialect);
        $inst->ensureRegistry();
        // ensure no stale installer lock and tag this run
        putenv('BC_ORCH_LOCK_EXTRA=test');
        $_ENV['BC_ORCH_LOCK_EXTRA'] = 'test';
        try { $db->exec('SELECT RELEASE_LOCK(:n)', [':n'=>'blackcat:orch:' . $db->id() . ':test']); } catch (\Throwable) {}

        $rt = new Runtime($db, $dialect, new NullLogger());
        $orc = new Orchestrator($rt);

        $mods = [
            new class implements ModuleInterface {
                public function name(): string { return 'A'; }
                public function table(): string { return 'a'; }
                public function version(): string { return '1.0.0'; }
                public function dialects(): array { return [ModuleInterface::DIALECT_MYSQL, ModuleInterface::DIALECT_POSTGRES]; }
                public function dependencies(): array { return []; }
                public function install(Database $db, SqlDialect $d): void {}
                public function upgrade(Database $db, SqlDialect $d, string $from): void {}
                public function uninstall(Database $db, SqlDialect $d): void {}
                public function status(Database $db, SqlDialect $d): array { return ['table'=>true,'view'=>true]; }
                public function info(): array { return []; }
                public static function contractView(): string { return 'a_view'; }
            },
            new class implements ModuleInterface {
                public function name(): string { return 'B'; }
                public function table(): string { return 'b'; }
                public function version(): string { return '1.0.0'; }
                public function dialects(): array { return [ModuleInterface::DIALECT_MYSQL, ModuleInterface::DIALECT_POSTGRES]; }
                public function dependencies(): array { return []; }
                public function install(Database $db, SqlDialect $d): void {}
                public function upgrade(Database $db, SqlDialect $d, string $from): void {}
                public function uninstall(Database $db, SqlDialect $d): void {}
                public function status(Database $db, SqlDialect $d): array { return ['table'=>true,'view'=>true]; }
                public function info(): array { return []; }
                public static function contractView(): string { return 'b_view'; }
            },
        ];
        $reg = new Registry(...$mods);

        $status = $orc->status($reg);
        $this->assertSame(2, $status['summary']['total']);

        $orc->installOrUpgradeOne($mods[0]);
        $this->assertTrue(true);

        // restore env
        if ($oldSchemaDir === null) {
            putenv('BC_SCHEMA_DIR');
            unset($_ENV['BC_SCHEMA_DIR']);
        } else {
            putenv("BC_SCHEMA_DIR={$oldSchemaDir}");
            $_ENV['BC_SCHEMA_DIR'] = $oldSchemaDir;
        }
    }
}
