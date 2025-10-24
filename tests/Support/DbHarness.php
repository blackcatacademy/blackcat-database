<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use BlackCat\Core\Database;
use BlackCat\Database\Installer;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Contracts\ModuleInterface;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use FilesystemIterator;

/**
 * Sdílená obsluha DB a modulů pro testy.
 */
final class DbHarness
{
    /** nainstaluje všechny moduly, idempotentně */
    public static function ensureInstalled(): array
    {
        $db = Database::getInstance();
        $driver  = $db->getPdo()->getAttribute(\PDO::ATTR_DRIVER_NAME);
        $dialect = $driver === 'mysql' ? SqlDialect::mysql : SqlDialect::postgres;

        $mods = self::discoverModules($dialect);
        $installer = new Installer($db, $dialect);
        $installer->ensureRegistry();
        foreach ($mods as $m) {
            $installer->installOrUpgrade($m);
            // druhý běh (idempotent)
            $installer->installOrUpgrade($m);
        }
        return $mods;
    }

    /** najde a instancuje všechny Module třídy kompatibilní s daným dialektem */
    public static function discoverModules(SqlDialect $dialect): array
    {
        $root = realpath(__DIR__ . '/../../packages');
        if ($root === false) {
            throw new \RuntimeException('packages/ not found');
        }
        $mods = [];
        $it = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)
        );
        foreach ($it as $f) {
            if (!$f->isFile()) continue;
            if (!preg_match('~/packages/([^/]+)/src/([A-Za-z0-9_]+)Module\.php$~', $f->getPathname(), $m)) continue;

            $pkgDir = $m[1];
            $pkgPascal = implode('', array_map(fn($x)=>ucfirst($x), preg_split('/[_-]/', $pkgDir)));
            $class = "BlackCat\\Database\\Packages\\{$pkgPascal}\\{$pkgPascal}Module";
            if (!class_exists($class)) { require_once $f->getPathname(); }
            if (!class_exists($class)) { throw new \RuntimeException("Module class not found: $class"); }

            /** @var ModuleInterface $obj */
            $obj = new $class();
            if (!in_array($dialect->value, $obj->dialects(), true)) continue;
            $mods[] = $obj;
        }
        // seřaď dle závislostí (topologicky, stejně jako v run.php)
        $index = [];
        foreach ($mods as $m) { $index[$m->name()] = $m; }
        $graph = $in = [];
        foreach ($mods as $m) { $graph[$m->name()] = []; $in[$m->name()] = 0; }
        foreach ($mods as $m) {
            foreach ($m->dependencies() as $dep) {
                if (isset($graph[$dep])) { $graph[$dep][] = $m->name(); $in[$m->name()]++; }
            }
        }
        $q = array_keys(array_filter($in, fn($d)=>$d===0));
        $out = [];
        while ($q) {
            $n = array_shift($q);
            $out[] = $index[$n];
            foreach ($graph[$n] as $m) { if (--$in[$m]===0) $q[]=$m; }
        }
        if (count($out) !== count($mods)) throw new \RuntimeException('Dependency cycle among modules');
        return $out;
    }

    /** Vrátí dvojici [SqlDialect, PDO driver string] */
    public static function dialect(): array
    {
        $driver  = Database::getInstance()->getPdo()->getAttribute(\PDO::ATTR_DRIVER_NAME);
        return [$driver === 'mysql' ? SqlDialect::mysql : SqlDialect::postgres, $driver];
    }

    /** info o sloupcích tabulky z information_schema (unifikované) */
    public static function columns(string $table): array
    {
        [$dial] = self::dialect();
        $db = Database::getInstance();

        if ($dial->isMysql()) {
            $sql = "SELECT COLUMN_NAME AS name, DATA_TYPE AS type, COLUMN_TYPE AS full_type,
                           IS_NULLABLE='YES' AS nullable,
                           COLUMN_DEFAULT AS col_default,
                           EXTRA LIKE '%auto_increment%' AS is_identity
                    FROM information_schema.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t
                    ORDER BY ORDINAL_POSITION";
        } else {
            $sql = "SELECT column_name AS name, data_type AS type, udt_name AS full_type,
                           is_nullable='YES' AS nullable,
                           column_default AS col_default,
                           (is_identity='YES' OR column_default LIKE 'nextval(%') AS is_identity
                    FROM information_schema.columns
                    WHERE table_schema='public' AND table_name = :t
                    ORDER BY ordinal_position";
        }
        return $db->fetchAll($sql, [':t'=>$table]);
    }

    /** názvy FK constraintů a sloupců (kvůli bezpečnému CRUD výběru tabulek) */
    public static function foreignKeyColumns(string $table): array
    {
        [$dial] = self::dialect();
        $db = Database::getInstance();

        if ($dial->isMysql()) {
            $sql = "SELECT k.COLUMN_NAME AS col
                    FROM information_schema.KEY_COLUMN_USAGE k
                    WHERE k.TABLE_SCHEMA=DATABASE() AND k.TABLE_NAME=:t AND k.REFERENCED_TABLE_NAME IS NOT NULL";
        } else {
            $sql = "SELECT kcu.column_name AS col
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu
                     ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
                    WHERE tc.table_schema='public' AND tc.table_name=:t AND tc.constraint_type='FOREIGN KEY'";
        }
        $rows = $db->fetchAll($sql, [':t'=>$table]) ?? [];
        return array_map(fn($r)=>$r['col'], $rows);
    }

    /** Hrubé vyčištění dat mezi testy (transakční přístup je preferovaný). */
    public static function begin(): void { Database::getInstance()->beginTransaction(); }
    public static function rollback(): void { Database::getInstance()->rollBack(); }
}
