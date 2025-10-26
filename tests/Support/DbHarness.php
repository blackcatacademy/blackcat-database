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
 * DB test harness + registry + FK/UNIQUE detaily + helpers pro PK/unique.
 */
final class DbHarness
{
    /** @var array<string,array{ns:string,repo:string,defs:string,view:?string}> */
    private static array $registry = [];

    /** nainstaluje všechny moduly, idempotentně + sestaví registry */
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
            $installer->installOrUpgrade($m); // idempotence
        }
        self::buildRegistry($mods);
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
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
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
        // topologické řazení dle závislostí
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
            foreach ($graph[$n] as $x) { if (--$in[$x]===0) $q[]=$x; }
        }
        if (count($out) !== count($mods)) throw new \RuntimeException('Dependency cycle among modules');
        return $out;
    }

    private static function fetchPkByRowMatch(string $table, array $row, string $pkCol = 'id'): mixed
    {
        $db = Database::getInstance();
        $pkExpr  = $db->quoteIdent($pkCol);
        $tabExpr = $db->quoteIdent($table);

        // Jen sloupce, které v tabulce skutečně existují
        $metaCols = array_fill_keys(array_map(fn($c) => (string)$c['name'], self::columns($table)), true);

        $conds = []; $params = [];
        foreach ($row as $k => $v) {
            if (!isset($metaCols[$k])) continue;
            if ($v === null) continue; // NULL rovnost by nic nenašla
            $conds[] = $db->quoteIdent($k) . ' = :' . $k;
            $params[':'.$k] = $v;
        }
        if (!$conds) return null;

        // Pokud řádek splňuje víc záznamů (neměl by), vezmeme poslední (PK DESC)
        $sql = "SELECT {$pkExpr}
                FROM {$tabExpr}
                WHERE " . implode(' AND ', $conds) . "
                ORDER BY {$pkExpr} DESC
                LIMIT 1";

        return $db->fetchValue($sql, $params, null);
    }

    /** Vybuduje registr {table => ns/repo/defs/view} z dostupných modulů. */
    private static function buildRegistry(array $mods): void
    {
        self::$registry = [];
        foreach ($mods as $m) {
            if (!method_exists($m, 'table')) continue;
            $table = (string)$m->table();
            $cls   = get_class($m); // …\Packages\X\XModule → základ …\Packages\X
            $nsBase = (string)preg_replace('~\\\[^\\\]+$~', '', $cls);
            $nsBase = (string)preg_replace('~Module$~', '', $nsBase);
            if (str_ends_with($nsBase, '\\')) $nsBase = substr($nsBase, 0, -1);

            $repo = $nsBase . '\\Repository';
            $defs = $nsBase . '\\Definitions';

            $view = null;
            if (class_exists($defs) && method_exists($defs, 'contractView')) {
                try { $view = (string)$defs::contractView(); } catch (\Throwable $_) {}
            }

            self::$registry[$table] = ['ns'=>$nsBase,'repo'=>$repo,'defs'=>$defs,'view'=>$view];
        }
    }

    /** lazy registry */
    private static function ensureRegistry(): void
    {
        if (self::$registry) return;
        [$dial] = self::dialect();
        $mods = self::discoverModules($dial);
        self::buildRegistry($mods);
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

    /**
     * Detaily cizích klíčů (seskupené podle constraintu).
     * @return array<int,array{name:string,cols:array<int,string>,ref_table:string,ref_cols:array<int,string>,nullable:array<int,bool>}>
     */
    public static function foreignKeysDetailed(string $table): array
    {
        [$dial] = self::dialect();
        $db = Database::getInstance();

        if ($dial->isMysql()) {
            $sql = "SELECT k.CONSTRAINT_NAME AS name,
                           k.COLUMN_NAME AS col,
                           k.REFERENCED_TABLE_NAME AS ref_table,
                           k.REFERENCED_COLUMN_NAME AS ref_col,
                           (SELECT IS_NULLABLE='YES' FROM information_schema.COLUMNS c
                             WHERE c.TABLE_SCHEMA = DATABASE() AND c.TABLE_NAME = k.TABLE_NAME AND c.COLUMN_NAME = k.COLUMN_NAME) AS is_nullable
                    FROM information_schema.KEY_COLUMN_USAGE k
                    JOIN information_schema.REFERENTIAL_CONSTRAINTS r
                      ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
                    WHERE k.TABLE_SCHEMA = DATABASE() AND k.TABLE_NAME = :t AND k.REFERENCED_TABLE_NAME IS NOT NULL
                    ORDER BY k.POSITION_IN_UNIQUE_CONSTRAINT";
        } else {
            $sql = "SELECT tc.constraint_name AS name,
                           kcu.column_name AS col,
                           ccu.table_name AS ref_table,
                           ccu.column_name AS ref_col,
                           (SELECT is_nullable='YES' FROM information_schema.columns c
                             WHERE c.table_schema='public' AND c.table_name = tc.table_name AND c.column_name = kcu.column_name) AS is_nullable
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu
                      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
                    JOIN information_schema.constraint_column_usage ccu
                      ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
                    WHERE tc.table_schema = 'public' AND tc.table_name = :t AND tc.constraint_type='FOREIGN KEY'
                    ORDER BY kcu.ordinal_position";
        }
        $rows = $db->fetchAll($sql, [':t'=>$table]) ?? [];
        $grp = [];
        foreach ($rows as $r) {
            $name = (string)$r['name'];
            if (!isset($grp[$name])) {
                $grp[$name] = ['name'=>$name,'cols'=>[],'ref_table'=>(string)$r['ref_table'],'ref_cols'=>[],'nullable'=>[]];
            }
            $grp[$name]['cols'][]     = (string)$r['col'];
            $grp[$name]['ref_cols'][] = (string)$r['ref_col'];
            $grp[$name]['nullable'][] = (bool)$r['is_nullable'];
        }
        return array_values($grp);
    }

    /** pouze názvy FK sloupců (kompatibilita) */
    public static function foreignKeyColumns(string $table): array
    {
        $fks = self::foreignKeysDetailed($table);
        $out = [];
        foreach ($fks as $fk) foreach ($fk['cols'] as $c) $out[] = $c;
        return $out;
    }

    /** Definitions::columns() pro whitelist; fallback na information_schema když není. */
    public static function allowedColumns(string $table): array
    {
        try {
            $defs = self::definitionsFor($table);
            if (class_exists($defs) && method_exists($defs, 'columns')) {
                $cols = (array)$defs::columns();
                if ($cols) return array_values(array_map('strval', $cols));
            }
        } catch (\Throwable $_) {}
        // fallback
        return array_map(fn($c)=>(string)$c['name'], self::columns($table));
    }

    /** Unikátní klíče ze schématu (information_schema) – včetně PK. */
    public static function uniqueKeysFromSchema(string $table): array
    {
        [$dial] = self::dialect();
        $db = Database::getInstance();

        if ($dial->isMysql()) {
            $sql = "SELECT tc.CONSTRAINT_NAME AS name, kcu.COLUMN_NAME AS col, kcu.ORDINAL_POSITION AS pos
                    FROM information_schema.TABLE_CONSTRAINTS tc
                    JOIN information_schema.KEY_COLUMN_USAGE kcu
                      ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
                     AND tc.TABLE_SCHEMA   = kcu.TABLE_SCHEMA
                     AND tc.TABLE_NAME     = kcu.TABLE_NAME
                    WHERE tc.TABLE_SCHEMA = DATABASE()
                      AND tc.TABLE_NAME   = :t
                      AND tc.CONSTRAINT_TYPE IN ('UNIQUE','PRIMARY KEY')
                    ORDER BY tc.CONSTRAINT_NAME, kcu.ORDINAL_POSITION";
        } else {
            $sql = "SELECT tc.constraint_name AS name, kcu.column_name AS col, kcu.ordinal_position AS pos
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu
                      ON tc.constraint_name = kcu.constraint_name
                     AND tc.table_schema   = kcu.table_schema
                     AND tc.table_name     = kcu.table_name
                    WHERE tc.table_schema = 'public'
                      AND tc.table_name   = :t
                      AND tc.constraint_type IN ('UNIQUE','PRIMARY KEY')
                    ORDER BY tc.constraint_name, kcu.ordinal_position";
        }

        $rows = $db->fetchAll($sql, [':t'=>$table]) ?? [];
        $grp = [];
        foreach ($rows as $r) {
            $n = (string)$r['name'];
            $grp[$n] ??= [];
            $grp[$n][] = (string)$r['col'];
        }
        // vrať pole unikátů jako pole sloupců v definovaném pořadí
        $out = [];
        foreach ($grp as $cols) {
            $out[] = array_values($cols);
        }
        return $out;
    }

    /** Unikátní klíče z Definitions (mohou být prázdné). */
    public static function uniqueKeys(string $table): array
    {
        try {
            $defs = self::definitionsFor($table);
            if (class_exists($defs) && method_exists($defs, 'uniqueKeys')) {
                return (array)$defs::uniqueKeys();
            }
        } catch (\Throwable $_) {}
        return [];
    }

    /** Definitions ∪ Schema, odfiltrované na povolené sloupce (repo je propustí). */
    public static function resolvedUniqueKeys(string $table): array
    {
        $allowed = array_fill_keys(self::allowedColumns($table), true);

        // definované v aplikaci
        $decl = [];
        foreach (self::uniqueKeys($table) as $uk) {
            $cols = array_values(array_filter(array_map('strval', (array)$uk)));
            if ($cols && !array_diff($cols, array_keys($allowed))) $decl[] = $cols;
        }
        // introspektované ze schématu
        $schema = [];
        foreach (self::uniqueKeysFromSchema($table) as $uk) {
            $cols = array_values(array_filter(array_map('strval', (array)$uk)));
            if ($cols && !array_diff($cols, array_keys($allowed))) $schema[] = $cols;
        }

        // sjednocení bez duplicit (množiny)
        $seen = [];
        $out  = [];
        $add = function(array $cols) use (&$seen,&$out) {
            $key = implode("\x1F", $cols);
            if (!isset($seen[$key])) { $seen[$key]=true; $out[]=$cols; }
        };
        foreach ($decl as $c)   $add($c);
        foreach ($schema as $c) $add($c);

        return $out;
    }

    /** Repo facade FQN + instance pro tabulku */
    public static function repoFor(string $table): object
    {
        self::ensureRegistry();
        $inf = self::$registry[$table] ?? null;
        if (!$inf) throw new \RuntimeException("Repository not found for table: {$table}");
        $cls = $inf['repo'];
        if (!class_exists($cls)) { /* autoloader */ }
        return new $cls(Database::getInstance());
    }

    /** Definitions FQN (třída s metadaty) */
    public static function definitionsFor(string $table): string
    {
        self::ensureRegistry();
        $inf = self::$registry[$table] ?? null;
        if (!$inf) throw new \RuntimeException("Definitions not found for table: {$table}");
        return $inf['defs'];
    }

    /** Primární klíč podle Definitions::pk() (fallback 'id') */
    public static function primaryKey(string $table): string
    {
        try {
            $defs = self::definitionsFor($table);
            if (class_exists($defs) && method_exists($defs, 'pk')) {
                return (string)$defs::pk();
            }
        } catch (\Throwable $_) {}
        return 'id';
    }

    /** Contract view podle Definitions (fallback tabulka) */
    public static function contractView(string $table): string
    {
        try {
            $defs = self::definitionsFor($table);
            if (class_exists($defs) && method_exists($defs, 'contractView')) {
                $v = (string)$defs::contractView();
                return $v !== '' ? $v : $table;
            }
        } catch (\Throwable $_) {}
        return $table;
    }

    /** Hrubé vyčištění dat mezi testy (transakční přístup je preferovaný). */
    public static function begin(): void { Database::getInstance()->beginTransaction(); }
    public static function rollback(): void { Database::getInstance()->rollBack(); }

    /**
     * Vloží řádek přes repo a zkusí vrátit PK (row[pk] / lastInsertId / dohledání přes unique).
     * @return array{pkCol:string,pk:mixed}|null
     */
    public static function insertAndReturnId(string $table, array $row): ?array
    {
        $repo  = self::repoFor($table);
        $pkCol = self::primaryKey($table);

        // 0) Efektivně vložené sloupce (ty, které Repository propustí)
        $allowedSet = array_fill_keys(self::allowedColumns($table), true);
        $rowUsed    = array_intersect_key($row, $allowedSet);

        // Když volající přinesl PK – rovnou ho vraťme.
        if (array_key_exists($pkCol, $rowUsed) && $rowUsed[$pkCol] !== null && $rowUsed[$pkCol] !== '') {
            $repo->insert($rowUsed);
            return ['pkCol'=>$pkCol, 'pk'=>$rowUsed[$pkCol]];
        }

        // 1) INSERT
        $repo->insert($rowUsed);
        $db = Database::getInstance();

        // 2) lastInsertId()
        try {
            $id = $db->lastInsertId();
            if ($id !== null && $id !== '') {
                if (ctype_digit((string)$id)) $id = (int)$id;
                return ['pkCol'=>$pkCol, 'pk'=>$id];
            }
        } catch (\Throwable $_) {}

        // 3) Dohledání přes unikáty (Definitions ∪ schema) nad TABULKOU
        $found = self::fetchPkByUniqueKey($table, $rowUsed, $pkCol);
        if ($found !== null) return ['pkCol'=>$pkCol, 'pk'=>$found];

        // 4) Plný row-match podle efektivně vložených sloupců (ignoruje NULL a neexistující sloupce)
        $found = self::fetchPkByRowMatch($table, $rowUsed, $pkCol);
        if ($found !== null) return ['pkCol'=>$pkCol, 'pk'=>$found];

        // 5) PG fallback: currval(pg_get_serial_sequence('schema.table','pk'))
        try {
            if ($db->isPg()) {
                // většina modulů jede ve schématu 'public'
                $seqId = $db->fetchValue(
                    "SELECT currval(pg_get_serial_sequence(:t, :pk))",
                    [':t' => 'public.' . $table, ':pk' => $pkCol],
                    null
                );
                if ($seqId !== null && $seqId !== '') {
                    if (ctype_digit((string)$seqId)) $seqId = (int)$seqId;
                    return ['pkCol'=>$pkCol, 'pk'=>$seqId];
                }
            }
        } catch (\Throwable $_) {}

        // 6) Generický single-process fallback: poslední záznam dle PK (DESC)
        try {
            $pkExpr  = $db->quoteIdent($pkCol);
            $tabExpr = $db->quoteIdent($table);
            $lastId  = $db->fetchValue("SELECT {$pkExpr} FROM {$tabExpr} ORDER BY {$pkExpr} DESC LIMIT 1", [], null);
            if ($lastId !== null && $lastId !== '') {
                return ['pkCol'=>$pkCol, 'pk'=>$lastId];
            }
        } catch (\Throwable $_) {}

        return null;
    }

    /** Dohledá PK podle prvního splnitelného unique key (všechny jeho sloupce jsou v $row). */
    public static function fetchPkByUniqueKey(string $table, array $row, string $pkCol = 'id'): mixed
    {
        $db = Database::getInstance();
        $pkExpr  = $db->quoteIdent($pkCol);
        $tabExpr = $db->quoteIdent($table);

        foreach (self::resolvedUniqueKeys($table) as $cols) {
            if (!$cols) continue;

            $present = true; $w = []; $p = [];
            foreach ($cols as $c) {
                // musí být skutečně k dispozici a ne null (null by v SQL skončilo jako "col = NULL" ⇒ never true)
                if (!array_key_exists($c, $row) || $row[$c] === null) { $present = false; break; }
                $w[] = $db->quoteIdent($c) . ' = :' . $c;
                $p[':'.$c] = $row[$c];
            }
            if (!$present) continue;

            $sql = "SELECT {$pkExpr} FROM {$tabExpr} WHERE " . implode(' AND ', $w) . " LIMIT 1";
            $id  = $db->fetchValue($sql, $p, null);
            if ($id !== null) return $id;
        }

        // fallback – zkus plný row-match (už obdrží efektivně vložené sloupce)
        return self::fetchPkByRowMatch($table, $row, $pkCol);
    }
}
