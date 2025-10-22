#!/usr/bin/env php
<?php
declare(strict_types=1);

/**
 * Usage:
 *   php bin/generate-modules.php --from manifest.json --out libs/blackcat-database/packages --dialect mysql --force
 */

$options = getopt("", ["from:", "out:", "dialect::", "force::"]);
$manifestFile = $options['from'] ?? 'manifest.json';
$outBase       = rtrim($options['out'] ?? 'libs/blackcat-database/packages', '/');
$dialect       = strtolower($options['dialect'] ?? 'mysql');
$force         = isset($options['force']);

if (!file_exists($manifestFile)) {
    fwrite(STDERR, "Manifest not found: $manifestFile\n");
    exit(1);
}

$manifest = json_decode(file_get_contents($manifestFile), true, 512, JSON_THROW_ON_ERROR);
$tables = $manifest['Tables'] ?? [];
if (!$tables) { fwrite(STDERR, "No Tables in manifest.\n"); exit(1); }

foreach ($tables as $tableName => $def) {
    $package = $def['packageName'] ?? ('table-' . $tableName);
    $studly  = studly($tableName);
    $nsBase  = "BlackCat\\Database\\Packages\\$studly";

    $pkgDir  = "$outBase/$package";
    $srcDir  = "$pkgDir/src";
    $schemaDir = "$pkgDir/schema";
    @mkdir($schemaDir, 0777, true);
    @mkdir("$srcDir/Joins", 0777, true);

    // 001 table
    writeFile("$schemaDir/001_table.$dialect.sql", trim($def['create'] ?? ''), $force);

    // 002 indexes
    $idx = implode(";\n", array_map('ensureSemi', $def['indexes'] ?? []));
    if ($idx) writeFile("$schemaDir/002_indexes_deferred.$dialect.sql", $idx, $force);

    // 003 FKs
    $fks = implode(";\n", array_map('ensureSemi', $def['foreign_keys'] ?? []));
    if ($fks) writeFile("$schemaDir/003_foreign_keys.$dialect.sql", $fks, $force);

    // 004 view (contract)
    $cols = parseColumnsFromCreate($def['create'] ?? '');
    $sing = singular($tableName);
    $view = $def['contractView'] ?? ($tableName . '__v1');
    $selectCols = [];
    if (in_array('id', $cols, true)) {
        $selectCols[] = "  id AS {$sing}_id";
        foreach ($cols as $c) if ($c !== 'id') $selectCols[] = "  $c";
    } else {
        foreach ($cols as $c) $selectCols[] = "  $c";
    }
    $viewSql = "CREATE OR REPLACE VIEW $view AS\nSELECT\n" . implode(",\n", $selectCols) . "\nFROM $tableName;";
    writeFile("$schemaDir/004_views_contract.$dialect.sql", $viewSql, $force);

    // 005 seed (optional)
    if (!empty($def['seed'])) {
        writeFile("$schemaDir/005_seed.$dialect.sql", trim($def['seed']), $force);
    }

    // composer.json
    $composer = [
        "name" => "blackcat/database-$package",
        "type" => "library",
        "autoload" => ["psr-4" => [ $nsBase."\\" => "src/" ]],
        "require" => ["php" => "^8.2", "ext-pdo" => "*"]
    ];
    writeFile("$pkgDir/composer.json", json_encode($composer, JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES), $force);

    // README
    $readme = "# $package\n\nAuto-generated from central manifest. Do not edit schema/*.sql manually.\n";
    writeFile("$pkgDir/README.md", $readme, $force);

    // Definitions.php
    $defPhp = <<<PHP
<?php
declare(strict_types=1);

namespace $nsBase;

final class Definitions {
    public static function table(): string { return '$tableName'; }
    public static function contractView(): string { return '$view'; }
    public static function columns(): array { return %s; } // parsed from CREATE
}
PHP;
    writeFile("$srcDir/Definitions.php", sprintf($defPhp, var_export($cols, true)), $force);

    // Module.php
    $modulePhp = <<<PHP
<?php
declare(strict_types=1);

namespace $nsBase;

use BlackCat\Database\\SqlDialect;
use BlackCat\\Database\\Contracts\\ModuleInterface;
use BlackCat\\Core\\Database;

final class {$studly}Module implements ModuleInterface {
    public function name(): string { return '$package'; }
    public function table(): string { return '$tableName'; }
    public function version(): string { return '1.0.0'; }
    public function dialects(): array { return ['mysql']; }
    public function dependencies(): array { return []; }

    public function install(Database \$db, SqlDialect \$d): void {
        \$dir = __DIR__.'/../schema';
        foreach (['001_table','$dialect', '002_indexes_deferred','$dialect', '003_foreign_keys','$dialect', '004_views_contract','$dialect', '005_seed','$dialect'] as \$k=>\$v) {}
        foreach (['001_table', '002_indexes_deferred', '003_foreign_keys', '004_views_contract', '005_seed'] as \$part) {
            \$path = "\$dir/".\$part.".{$dialect}.sql";
            if (is_file(\$path)) { \$db->exec(file_get_contents(\$path)); }
        }
    }
    public function upgrade(Database \$db, SqlDialect \$d, string \$from): void { /* future versions */ }
    public function status(Database \$db, SqlDialect \$d): array {
        // minimal check: table and view exist
        \$t = self::table();
        \$v = self::contractView();
        \$hasTable = (bool)\$db->fetchOne("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?", [\$t]);
        \$hasView  = (bool)\$db->fetchOne("SELECT COUNT(*) FROM information_schema.VIEWS  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?", [\$v]);
        return ['table'=>\$hasTable,'view'=>\$hasView];
    }
    public function info(): array { return ['table'=>self::table(),'view'=>self::contractView(),'columns'=>Definitions::columns()]; }
}
PHP;
    writeFile("$srcDir/{$studly}Module.php", $modulePhp, $force);

    // Repository.php (skeleton)
    $repoPhp = <<<PHP
<?php
declare(strict_types=1);

namespace $nsBase;

use BlackCat\\Core\\Database;

final class Repository {
    public function __construct(private Database \$db) {}

    public function insert(array \$row): void {
        \$cols = array_keys(\$row);
        \$place = array_map(fn(\$c)=>':'.\$c, \$cols);
        \$sql = 'INSERT INTO $tableName ('.implode(',',\$cols).') VALUES ('.implode(',',\$place).')';
        \$this->db->execute(\$sql, array_combine(\$place, array_values(\$row)));
    }

    public function updateById(int \$id, array \$row): void {
        \$assign = [];
        \$params = [':id'=>\$id];
        foreach (\$row as \$k=>\$v) { \$assign[] = "\$k = :\$k"; \$params[":\$k"]=\$v; }
        \$sql = 'UPDATE $tableName SET '.implode(',',\$assign).' WHERE id = :id';
        \$this->db->execute(\$sql, \$params);
    }
}
PHP;
    writeFile("$srcDir/Repository.php", $repoPhp, $force);

    // Joins helper (podle FK)
    $refs = referencedTables($def['foreign_keys'] ?? []);
    $joinMethods = [];
    foreach ($refs as $refTable) {
        $m = 'leftJoin'.studly($refTable);
        $joinMethods[] = <<<PHP
    public static function $m(string \$leftAlias, string \$alias = 'j'): array {
        return ["LEFT JOIN $refTable \$alias ON \$alias.id = \$leftAlias.{$refTable}_id", []];
    }
PHP;
    }
    if (!$joinMethods) {
        $joinMethods[] = "    // No foreign keys detected; add joins as needed.\n";
    }
    $joinsPhp = <<<PHP
<?php
declare(strict_types=1);

namespace $nsBase\\Joins;

final class {$studly}Joins {
$joinMethods[0]
}
PHP;
    writeFile("$srcDir/Joins/{$studly}Joins.php", $joinsPhp, $force);

    echo "Generated: $package\n";
}

echo "DONE\n";

// === helpers ===
function writeFile(string $path, string $content, bool $force): void {
    if (file_exists($path) && !$force) return;
    file_put_contents($path, rtrim($content).(str_ends_with(trim($content), ';')? "\n" : "\n"));
}

function ensureSemi(string $sql): string {
    $s = rtrim($sql);
    return str_ends_with($s, ';') ? $s : $s.';';
}

function studly(string $s): string {
    return str_replace(' ', '', ucwords(str_replace(['_','-'], ' ', $s)));
}

function singular(string $name): string {
    if (str_ends_with($name, 'ies')) return substr($name, 0, -3).'y';
    if (str_ends_with($name, 'ses')) return substr($name, 0, -2);
    if (str_ends_with($name, 's')) return substr($name, 0, -1);
    return $name;
}

/** Naivní extrakce seznamu sloupců z CREATE TABLE (MySQL syntaxi). */
function parseColumnsFromCreate(string $createSql): array {
    $cols = [];
    if (!preg_match('/CREATE\\s+TABLE\\s+IF\\s+NOT\\s+EXISTS\\s+`?([a-zA-Z0-9_]+)`?\\s*\\((.*)\\)\\s*/is', $createSql, $m)) {
        if (!preg_match('/CREATE\\s+TABLE\\s+IF\\s+NOT\\s+EXISTS\\s+([a-zA-Z0-9_]+)\\s*\\((.*)\\)\\s*/is', $createSql, $m)) {
            return $cols;
        }
    }
    $body = $m[2];
    foreach (preg_split('/,(?![^\\(]*\\))/s', $body) as $line) {
        $line = trim($line, " \t\n\r\0\x0B`");
        if ($line === '') continue;
        $up = strtoupper($line);
        if (str_starts_with($up,'PRIMARY ') || str_starts_with($up,'UNIQUE ') || str_starts_with($up,'INDEX ')
            || str_starts_with($up,'KEY ') || str_starts_with($up,'CONSTRAINT ') || str_starts_with($up,'FOREIGN ')
            || str_starts_with($up,'CHECK ')) {
            continue;
        }
        // get first token as column name
        if (preg_match('/^([a-zA-Z0-9_`]+)/', $line, $mm)) {
            $col = trim($mm[1], '`');
            $cols[] = $col;
        }
    }
    return $cols;
}

/** Najde referenced tabulky v FK SQL. */
function referencedTables(array $fkSqls): array {
    $out = [];
    foreach ($fkSqls as $sql) {
        if (preg_match_all('/REFERENCES\\s+`?([a-zA-Z0-9_]+)`?/i', $sql, $m)) {
            foreach ($m[1] as $t) $out[$t] = true;
        }
    }
    return array_keys($out);
}
