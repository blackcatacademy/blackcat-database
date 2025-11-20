<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Util;

use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Contracts\ModuleInterface;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use FilesystemIterator;

final class DbUtil
{
    public static function db(): Database { return Database::getInstance(); }

    public static function dialect(): SqlDialect {
        $drv = self::db()->driver();
        return $drv === 'pgsql' ? SqlDialect::postgres : SqlDialect::mysql;
    }

    /** Drop and recreate a clean DB (safe for tests). */
    public static function wipeDatabase(): void
    {
        $db = self::db();
        if ($db->isMysql()) {
            // drop+create the current DB selected by DATABASE()
            $dbName = (string)$db->fetchValue("SELECT DATABASE()", [], '');
            if ($dbName !== '') {
                $db->exec("SET FOREIGN_KEY_CHECKS=0");
                $db->exec("DROP DATABASE IF EXISTS `{$dbName}`");
                $db->exec("CREATE DATABASE `{$dbName}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
                $db->exec("USE `{$dbName}`");
                $db->exec("SET FOREIGN_KEY_CHECKS=1");
            }
        } else {
            // Postgres: drop public schema
            $db->exec("DROP SCHEMA IF EXISTS public CASCADE");
            $db->exec("CREATE SCHEMA public");
            $db->exec("GRANT ALL ON SCHEMA public TO postgres");
            $db->exec("GRANT ALL ON SCHEMA public TO public");
        }
    }

    /** Discover all Module classes that support the current dialect. */
    public static function discoverModules(?string $packagesDir = null): array
    {
        $packagesDir = $packagesDir ?? realpath(__DIR__ . '/../../packages');
        if ($packagesDir === false) { return []; }

        $d = self::dialect();
        $modules = [];

        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($packagesDir, FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if (!$f->isFile()) continue;
            $path = $f->getPathname();
            if (!preg_match('~/packages/([^/]+)/src/([A-Za-z0-9_]+)Module\.php$~', $path, $m)) continue;

            $pkgDir = $m[1];
            $pkgPascal = implode('', array_map(fn($x)=>ucfirst($x), preg_split('/[_-]/', $pkgDir)));
            $class = "BlackCat\\Database\\Packages\\{$pkgPascal}\\{$pkgPascal}Module";

            require_once $path; // ensure autoload kicks in
            if (!class_exists($class)) continue;

            /** @var ModuleInterface $obj */
            $obj = new $class();
            if (!in_array($d->value, $obj->dialects(), true)) continue;

            $modules[] = $obj;
        }
        return $modules;
    }
}
