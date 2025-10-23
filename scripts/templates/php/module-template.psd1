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
use BlackCat\Core\Database;

final class [[CLASS]] implements ModuleInterface {
    public function name(): string { return 'table-[[TABLE]]'; }
    public function table(): string { return '[[TABLE]]'; }
    public function version(): string { return '[[VERSION]]'; }
    /** @return string[] */
    public function dialects(): array { return [[DIALECTS_ARRAY]]; }
    /** @return string[] */
    public function dependencies(): array { return [[DEPENDENCIES_ARRAY]]; }

    public function install(Database $db, SqlDialect $d): void {
        $dir  = __DIR__ . '/../schema';
        $dial = $d->isMysql() ? 'mysql' : 'postgres';

        // Primární pořadí + fallback na alternativní názvosloví
        $variants = [
            ['001_table', '002_indexes_deferred', '003_foreign_keys', '004_views_contract', '005_seed'],
            ['001_table', '020_indexes',          '030_foreign_keys', '040_view_contract',   '050_seed'],
        ];

        $seen = [];
        foreach ($variants as $parts) {
            foreach ($parts as $part) {
                $path = "$dir/$part.$dial.sql";
                if (isset($seen[$path]) || !is_file($path)) { continue; }
                $sql = (string)file_get_contents($path);
                if ($sql !== '') { $db->exec($sql); }
                $seen[$path] = true;
            }
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

        // ---- existence table/view
        $hasTable = (int)$db->fetchOne(
            $d->isMysql()
              ? "SELECT COUNT(*) FROM information_schema.TABLES
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t"
              : "SELECT COUNT(*) FROM information_schema.tables
                   WHERE table_schema = 'public' AND table_name = :t",
            [':t' => $table]
        ) > 0;

        $hasView = (int)$db->fetchOne(
            $d->isMysql()
              ? "SELECT COUNT(*) FROM information_schema.VIEWS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :v"
              : "SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_views WHERE viewname = :v) THEN 1 ELSE 0 END",
            [':v' => $view]
        ) > 0;

        // ---- rychlá kontrola indexů/FK (pokud generátor dodal názvy)
        $indexes = [[INDEX_NAMES_ARRAY]];
        $fks     = [[FK_NAMES_ARRAY]];
        $missingIdx = [];
        $missingFk  = [];

        if ($d->isMysql()) {
            foreach ($indexes as $ix) {
                if ($ix === '') continue;
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.STATISTICS
                     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND INDEX_NAME = :i",
                    [':t'=>$table, ':i'=>$ix]
                );
                if ($cnt === 0) { $missingIdx[] = $ix; }
            }
            foreach ($fks as $fk) {
                if ($fk === '') continue;
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.REFERENTIAL_CONSTRAINTS
                     WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME = :c",
                    [':c'=>$fk]
                );
                if ($cnt === 0) { $missingFk[] = $fk; }
            }
        } else {
            foreach ($indexes as $ix) {
                if ($ix === '') continue;
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM pg_indexes
                     WHERE schemaname = 'public' AND tablename = :t AND indexname = :i",
                    [':t'=>$table, ':i'=>$ix]
                );
                if ($cnt === 0) { $missingIdx[] = $ix; }
            }
            foreach ($fks as $fk) {
                if ($fk === '') continue;
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.table_constraints
                     WHERE table_schema = 'public' AND table_name = :t
                       AND constraint_name = :c AND constraint_type='FOREIGN KEY'",
                    [':t'=>$table, ':c'=>$fk]
                );
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
