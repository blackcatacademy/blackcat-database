@{
  File   = 'src/[[CLASS]].php'  # např. UsersModule.php
  Tokens = @(
    'NAMESPACE','CLASS','TABLE','VIEW','VERSION','DIALECTS_ARRAY',
    'DEPENDENCIES_ARRAY','INDEX_NAMES_ARRAY','FK_NAMES_ARRAY'
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

use BlackCat\Database\SqlDialect;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Core\Database\Database;

final class [[CLASS]] implements ModuleInterface {
    public function name(): string { return 'table-[[TABLE]]'; }
    public function table(): string { return '[[TABLE]]'; }
    public function version(): string { return '[[VERSION]]'; }
    /** @return string[] */
    public function dialects(): array { return [[DIALECTS_ARRAY]]; }
    /** @return string[] */
    public function dependencies(): array { return [[DEPENDENCIES_ARRAY]]; }

    public function install(Database $db, SqlDialect $d): void {
        $dir = __DIR__ . '/../schema';
        $dial = $d->isMysql() ? 'mysql' : 'postgres';
        foreach (['001_table', '002_indexes_deferred', '003_foreign_keys', '004_views_contract', '005_seed'] as $part) {
            $path = "$dir/$part.$dial.sql";
            if (is_file($path)) { $db->exec(file_get_contents($path)); }
        }
    }

    public function upgrade(Database $db, SqlDialect $d, string $from): void {
        // sem může generátor vkládat idempotentní ALTER/CREATE kroky na základě $from
    }

    /** Volitelné: nenabízí DROP TABLE, pouze kontrakt (view). */
    public function uninstall(Database $db, SqlDialect $d): void {
        $view = '[[VIEW]]';
        if ($d->isMysql()) {
            $db->exec("DROP VIEW IF EXISTS `$view`");
        } else {
            $db->exec("DROP VIEW IF EXISTS $view");
        }
    }

    public function status(Database $db, SqlDialect $d): array {
        $table = '[[TABLE]]';
        $view  = '[[VIEW]]';

        $hasTable = (bool)$db->fetchOne(
            $d->isMysql()
              ? "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?"
              : "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = $1",
            $d->isMysql() ? [$table] : [$table]
        );
        $hasView = (bool)$db->fetchOne(
            $d->isMysql()
              ? "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?"
              : "SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname = $1)",
            $d->isMysql() ? [$view] : [$view]
        );

        // Rychlé ověření přítomnosti indexů/FK podle názvů (pokud jsou poskytnuty tokeny)
        $indexes = [[INDEX_NAMES_ARRAY]];
        $fks     = [[FK_NAMES_ARRAY]];
        $missingIdx = [];
        $missingFk  = [];

        if ($d->isMysql()) {
            foreach ($indexes as $ix) {
                if ($ix === '') continue;
                $cnt = (int)$db->fetchOne("SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?", [$table, $ix]);
                if ($cnt === 0) { $missingIdx[] = $ix; }
            }
            foreach ($fks as $fk) {
                if ($fk === '') continue;
                $cnt = (int)$db->fetchOne("SELECT COUNT(*) FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME = ?", [$fk]);
                if ($cnt === 0) { $missingFk[] = $fk; }
            }
        } else {
            foreach ($indexes as $ix) {
                if ($ix === '') continue;
                $cnt = (int)$db->fetchOne("SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public' AND tablename = $1 AND indexname = $2", [$table, $ix]);
                if ($cnt === 0) { $missingIdx[] = $ix; }
            }
            foreach ($fks as $fk) {
                if ($fk === '') continue;
                $cnt = (int)$db->fetchOne("
                  SELECT COUNT(*) FROM information_schema.table_constraints
                  WHERE table_schema = 'public' AND table_name = $1 AND constraint_name = $2 AND constraint_type='FOREIGN KEY'
                ", [$table, $fk]);
                if ($cnt === 0) { $missingFk[] = $fk; }
            }
        }

        return [
            'table'        => $hasTable,
            'view'         => $hasView,
            'missing_idx'  => $missingIdx,
            'missing_fk'   => $missingFk,
            'version'      => $this->version(),
        ];
    }

    public function info(): array {
        return [
            'table'   => self::table(),
            'view'    => self::contractView(),
            'columns' => Definitions::columns(),
            'version' => $this->version(),
        ];
    }

    public static function contractView(): string { return '[[VIEW]]'; }
}
'@
}
