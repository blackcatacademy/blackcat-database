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
 * DbHarness – testovací “lešení” pro databázi (MySQL/Postgres) s bohatým logováním přes BC_DEBUG=1.
 *
 * - Instaluje/upgradeuje moduly (Installer), hlídá pořadí závislostí.
 * - Staví registr tabulek → Definitions/Repository FQN.
 * - Unifikované introspekce: sloupce, FK (detaily), unique key (schema+definitions), enum-like volby.
 * - Helpery pro vložení řádku a dohledání PK.
 *
 * LOGGING: nastavte BC_DEBUG=1 (nebo true) pro podrobné logy (stderr).
 */
final class DbHarness
{
    /** @var array<string,array{ns:string,repo:?string,defs:string,view:?string}> */
    private static array $registry = [];

    // -------------------- DEBUG --------------------

    private static function isDebug(): bool
    {
        $v = $_ENV['BC_DEBUG'] ?? getenv('BC_DEBUG') ?? '';
        return $v === '1' || strcasecmp((string)$v, 'true') === 0;
    }

    private static function dbg(string $fmt, mixed ...$args): void
    {
        if (!self::isDebug()) return;
        error_log('[DbHarness] ' . vsprintf($fmt, $args));
    }

    private static function normalizeUtf8(string $s): string
    {
        if (mb_check_encoding($s, 'UTF-8')) return $s;
        foreach (['Windows-1250','Windows-1252','ISO-8859-2','ISO-8859-1'] as $enc) {
            $t = @mb_convert_encoding($s, 'UTF-8', $enc);
            if ($t !== false && mb_check_encoding($t, 'UTF-8')) return $t;
        }
        return $s; // poslední možnost – vrať bez konverze
    }

    private static function mysqlErrno(\Throwable $e): ?int
    {
        return ($e instanceof \PDOException && isset($e->errorInfo[1]))
            ? (int)$e->errorInfo[1]
            : null;
    }

    /** SQLSTATE z PDO výjimky (např. 42S02, 42P01). */
    private static function sqlState(\Throwable $e): ?string
    {
        return ($e instanceof \PDOException && isset($e->errorInfo[0]))
            ? (string)$e->errorInfo[0]
            : null;
    }

    /** Chyby „objekt neexistuje“ – vhodné tlumit na dbg. */
    private static function isBenignMissing(\Throwable $e): bool
    {
        $errno = self::mysqlErrno($e);
        $state = self::sqlState($e);
        return $errno === 1146 || $state === '42S02' || $state === '42P01';
    }

    /** Jednorázový warn (stejné hlášky nespamují log). */
    private static array $warnOnceCache = [];
    private static function warnOnce(string $key, string $fmt, mixed ...$args): void
    {
        if (isset(self::$warnOnceCache[$key])) return;
        self::$warnOnceCache[$key] = true;
        self::warn($fmt, ...$args);
    }

    private static function logDbError(string $ctx, \Throwable $e, bool $treatMissingAsDbg = true, ?string $onceKey = null): void
    {
        $msg   = self::normalizeUtf8($e->getMessage());
        $errno = self::mysqlErrno($e);
        $state = self::sqlState($e);

        if ($treatMissingAsDbg && self::isBenignMissing($e)) {
            self::dbg('%s: missing object (errno=%s, sqlstate=%s): %s', $ctx, $errno ?? '-', $state ?? '-', $msg);
            return;
        }
        $line = sprintf('%s failed (errno=%s, sqlstate=%s): %s', $ctx, $errno ?? '-', $state ?? '-', $msg);
        if ($onceKey) {
            self::warnOnce($onceKey, '%s', $line);
        } else {
            self::warn('%s', $line);
        }
    }

    private static function warn(string $fmt, mixed ...$args): void
    {
        // normalize všechny stringové argumenty do UTF-8 (kvůli mojibake)
        foreach ($args as $i => $a) {
            if (is_string($a)) $args[$i] = self::normalizeUtf8($a);
        }
        error_log('[DbHarness][WARN] ' . vsprintf($fmt, $args));
    }

    // === TRACE_VIEWS (tichý režim: aktivní jen při BC_TRACE_VIEWS=1/true) =======================
    private static function traceViewsEnabled(): bool
    {
        $v = $_ENV['BC_TRACE_VIEWS'] ?? getenv('BC_TRACE_VIEWS') ?? '';
        return $v === '1' || strcasecmp((string)$v, 'true') === 0;
    }

    private static function tv(string $fmt, mixed ...$args): void
    {
        if (!self::traceViewsEnabled()) return;
        error_log('[DbHarness][TRACE_VIEWS] ' . vsprintf($fmt, $args));
    }

    // --- Cache controls (add to class DbHarness) ---
    private static function cacheDisabled(): bool {
        $v = $_ENV['BC_NO_CACHE'] ?? getenv('BC_NO_CACHE') ?? '';
        return $v === '1' || strcasecmp((string)$v, 'true') === 0;
    }
    private static function cacheSuffix(): string {
        return (string)($_ENV['BC_CACHE_BUSTER'] ?? getenv('BC_CACHE_BUSTER') ?? '');
    }

    /** Volitelné: shodí high-level registry; cache buster pro per-method caches změň přes env. */
    public static function clearProcessCaches(): void {
        self::$registry = [];
    }
    /** Volitelné: lokálně „bumpni“ cache buster i bez restartu procesu. */
    public static function bumpCacheBuster(): void {
        @putenv('BC_CACHE_BUSTER=' . (string)microtime(true));
    }
    
    // -------------------- PUBLIC API --------------------

    /** Nainstaluje všechny moduly idempotentně + sestaví registry. Vrací seznam modulů. */
    public static function ensureInstalled(): array
    {
        self::$bootstrapped = true; // aby bootstrapOnce() už nezkoušelo instalovat znovu
        $db = Database::getInstance();
        $pdo = $db->getPdo();
        $driver = (string)$pdo->getAttribute(\PDO::ATTR_DRIVER_NAME);
        $dialect = $driver === 'mysql' ? SqlDialect::mysql : SqlDialect::postgres;

        self::dbg('ensureInstalled: driver=%s dialect=%s', $driver, $dialect->value);

        // PG: zajisti schema a search_path (BC_PG_SCHEMA nebo 'public')
        if ($dialect->isPg()) {
            $schema = self::pgSchema();
            self::dbg('ensureInstalled: PG schema=%s → CREATE IF NOT EXISTS + SET search_path', $schema);
            try {
                $db->exec('CREATE SCHEMA IF NOT EXISTS ' . $db->quoteIdent($schema));
            } catch (\Throwable $e) {
                self::logDbError('CREATE SCHEMA', $e);
            }
            try {
                $db->exec("SET search_path TO " . $db->quoteIdent($schema) . ", public");
            } catch (\Throwable $e) {
                self::logDbError('SET search_path', $e);
            }
        } else {
            // MySQL: zaloguj aktivní databázi
            try {
                $curDb = (string)($db->fetchOne('SELECT DATABASE()') ?? '');
                self::dbg('ensureInstalled: MySQL DATABASE()=%s', $curDb !== '' ? $curDb : '(NULL)');
            } catch (\Throwable $e) {
                self::logDbError('SELECT DATABASE()', $e, false, 'select-database');
            }
        }

        // Najdi moduly a proveď install/upgrade
        $mods = self::discoverModules($dialect);
        $installer = new Installer($db, $dialect);
        $installer->ensureRegistry();

        // volitelně zpřísnit chování Installeru přímo z Harnessu
        $strictViews = self::envTrue('BC_HARNESS_STRICT_VIEWS');
        $prevStrict  = getenv('BC_INSTALLER_STRICT_VIEWS') ?: '';
        if ($strictViews) { @putenv('BC_INSTALLER_STRICT_VIEWS=1'); }

        // 1) průchod – tabulky, indexy, seeds…
        foreach ($mods as $m) {
            self::dbg('Install pass #1: %s', $m->name());
            $installer->installOrUpgrade($m);
        }

        // 2) průchod – vynucený replay view (BC_REPAIR=1) + idempotence
        $prevRepair = getenv('BC_REPAIR') ?: '';
        @putenv('BC_REPAIR=1');
        foreach ($mods as $m) {
            self::dbg('Install pass #2 (views & idempotence): %s', $m->name());
            $installer->installOrUpgrade($m);
        }
        // restore env
        if ($prevRepair === '') { @putenv('BC_REPAIR'); } else { @putenv('BC_REPAIR='.$prevRepair); }
        if ($prevStrict === '') { @putenv('BC_INSTALLER_STRICT_VIEWS'); } else { @putenv('BC_INSTALLER_STRICT_VIEWS='.$prevStrict); }

        // 3) **ANTIRACE**: ověř, že všechna deklarovaná view skutečně existují; případně jednou oprav.
        self::verifyViewsOrRepair($mods, $installer, $dialect);

        // … dál už beze změny:
        if ($dialect->isPg()) {
            try {
                $schema = self::pgSchema();
                $db->exec("SET search_path TO " . $db->quoteIdent($schema) . ", public");
            } catch (\Throwable $e) {
                self::logDbError('Reset search_path', $e);
            }
        }

        self::buildRegistry($mods);
        if (self::traceViewsEnabled()) {
            self::traceViewsSnapshot();
        }

        // Smoke-check: zjisti, zda information_schema vidí tabulky
        try {
            if ($dialect->isPg()) {
                $schema = self::pgSchema();
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=:s",
                    [':s' => $schema]
                );
                self::dbg('ensureInstalled: PG information_schema.tables visible in schema=%s count=%d', $schema, $cnt);
            } else {
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()"
                );
                $curDb = (string)($db->fetchOne('SELECT DATABASE()') ?? '');
                self::dbg('ensureInstalled: MySQL information_schema.tables visible in DB=%s count=%d', $curDb, $cnt);
            }
        } catch (\Throwable $e) {
            self::logDbError('ensureInstalled: information_schema smoke-check', $e, false, 'smoke-check');
        }
        // Po instalaci/upgrade chceme nové introspekce → bump cache buster
        self::bumpCacheBuster();
        return $mods;
    }

    /** Najde a instancuje všechny Module třídy kompatibilní s daným dialektem (toposort). */
    public static function discoverModules(SqlDialect $dialect): array
    {
        $root = realpath(__DIR__ . '/../../packages');
        if ($root === false) {
            throw new \RuntimeException('packages/ not found at ' . (__DIR__ . '/../../packages'));
        }
        self::dbg('discoverModules: scanning %s', $root);

        $mods = [];
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
        foreach ($it as $f) {
            if (!$f->isFile()) continue;
            $path = str_replace('\\', '/', $f->getPathname());
            if (!preg_match('~/packages/([^/]+)/src/([A-Za-z0-9_]+)Module\.php$~', $path, $m)) continue;

            $pkgDir = $m[1];
            $pkgPascal = implode('', array_map(fn($x)=>ucfirst($x), preg_split('/[_-]/', $pkgDir)));
            $class = "BlackCat\\Database\\Packages\\{$pkgPascal}\\{$pkgPascal}Module";

            if (!class_exists($class)) {
                self::dbg('discoverModules: require %s', $path);
                require_once $f->getPathname();
            }
            if (!class_exists($class)) {
                throw new \RuntimeException("Module class not found: $class");
            }

            /** @var ModuleInterface $obj */
            $obj = new $class();
            $supported = $obj->dialects();
            if ($supported && !in_array($dialect->value, $supported, true)) {
                self::dbg('discoverModules: skip %s (dialects=%s)', $obj->name(), implode(',', $supported));
                continue;
            }
            $mods[] = $obj;
        }

        $sorted = self::toposort($mods);
        self::dbg('discoverModules: found=%d, after toposort=%d', count($mods), count($sorted));
        return $sorted;
    }

    /** Repo facade FQN + instance pro tabulku. */
    public static function repoFor(string $table): object
    {
        self::ensureRegistry();
        $inf = self::$registry[$table] ?? null;
        if (!$inf) {
            throw new \RuntimeException("Repository not found for table: {$table}");
        }

        $repoFqn = $inf['repo'];
        if (!$repoFqn || !class_exists($repoFqn)) {
            // registry může být z jiného běhu → zkus odvodit znovu
            $repoFqn = self::resolveRepoFqn($inf['ns'] ?? '', $inf['defs'] ?? '');
        }
        if (!$repoFqn || !class_exists($repoFqn)) {
            $ns = $inf['ns'] ?? '(unknown)';
            throw new \RuntimeException("Repository class not found for table '{$table}' under namespace '{$ns}'.");
        }
        self::dbg('repoFor(%s): %s', $table, $repoFqn);
        return new $repoFqn(Database::getInstance());
    }

    /** Definitions FQN (třída s metadaty). */
    public static function definitionsFor(string $table): string
    {
        self::ensureRegistry();
        $inf = self::$registry[$table] ?? null;
        if (!$inf) {
            throw new \RuntimeException("Definitions not found for table: {$table}");
        }
        return $inf['defs'];
    }

    /** Primární klíč podle Definitions::pk() (fallback 'id'). */
    public static function primaryKey(string $table): string
    {
        try {
            $defs = self::definitionsFor($table);
            if (class_exists($defs) && method_exists($defs, 'pk')) {
                $pk = (string)$defs::pk();
                if ($pk !== '') return $pk;
            }
        } catch (\Throwable $e) {
            self::dbg('primaryKey(%s): exception: %s → fallback id', $table, $e->getMessage());
        }
        return 'id';
    }

    /** Contract view (fallback tabulka). */
    public static function contractView(string $table): string
    {
        try {
            $defs = self::definitionsFor($table);
            if (class_exists($defs) && method_exists($defs, 'contractView')) {
                $v = (string)$defs::contractView();
                if ($v !== '') {
                    if (self::traceViewsEnabled()) self::tv('[CV] via Definitions: %s -> %s', $table, $v);
                    return $v;
                }
                if (self::traceViewsEnabled()) self::tv('[CV] Definitions empty for %s', $table);
            }
        } catch (\Throwable $e) {
            self::dbg('contractView(%s): defs exception: %s', $table, $e->getMessage());
        }

        $db = \BlackCat\Core\Database::getInstance();

        if (self::isMysql()) {
            // preferuj skutečné view „vw_<table>“ (respektuje prefixy přes resolvePhysicalName)
            $cand = 'vw_' . $table;
            $phys = self::resolvePhysicalName($cand);
            $isView = (int)$db->fetchOne(
                "SELECT COUNT(*) FROM information_schema.VIEWS
                WHERE TABLE_SCHEMA = DATABASE() AND LOWER(TABLE_NAME) = LOWER(:t)",
                [':t' => $phys]
            );

        if (self::traceViewsEnabled()) self::tv('[CV] MySQL: table=%s cand=vw_%s phys=%s isView=%d', $table, $table, $phys, $isView);
            if ($isView > 0) {
                if (self::traceViewsEnabled()) self::tv('[CV] DECISION: %s -> %s', $table, $phys);
                return $phys;
            }

        } else {
            $schema = self::pgSchema();
            $cand   = 'vw_' . $table;
            $isView = (int)$db->fetchOne(
                "SELECT COUNT(*) FROM information_schema.views
                WHERE table_schema = :s AND LOWER(table_name) = LOWER(:t)",
                [':s' => $schema, ':t' => $cand]
            );

        if (self::traceViewsEnabled()) self::tv('[CV] PG: table=%s cand=%s isView=%d (schema=%s)', $table, $cand, $isView, $schema);
            if ($isView > 0) {
                if (self::traceViewsEnabled()) self::tv('[CV] DECISION: %s -> %s', $table, $cand);
                return $cand;
            }

        }
        if (self::traceViewsEnabled()) self::tv('[CV] FALLBACK: %s -> %s (no view found)', $table, $table);
        // definitivní fallback: tabulka
        return $table;
    }

    public static function begin(): void { Database::getInstance()->beginTransaction(); }
    public static function rollback(): void { Database::getInstance()->rollBack(); }

    /**
     * Columns meta z information_schema (unifikované). Loguje důvody, když nic nenajde.
     * @return array<int,array{name:string,type:string,full_type:string,nullable:bool,col_default:mixed,is_identity:bool}>
     */
    public static function columns(string $table): array
    {
        static $cache = [];
        [$dial] = self::dialect(); /** @var SqlDialect $dial */
        $useCache = !self::cacheDisabled();
        $sfx = self::cacheSuffix();
        $db = Database::getInstance();

        $key = ($dial->isPg() ? 'pg:' . self::pgSchema() : 'mysql') . ':' . $table . ':' . $sfx;
        if ($useCache && isset($cache[$key])) { return $cache[$key]; }

        self::dbg('columns(%s): query information_schema (dialect=%s)', $table, $dial->value);

        if ($dial->isMysql()) {
            $phys = self::resolvePhysicalName($table);
            if (strcasecmp($phys, $table) !== 0) {
                self::dbg('columns(%s): resolved physical=%s', $table, $phys);
            }

            // cache klíč podle fyzického jména
            $keyPhys = 'mysql:' . $phys . ':' . $sfx;
            if ($useCache && isset($cache[$keyPhys])) { return $cache[$keyPhys]; }

            // information_schema nejdřív
            $sql = "SELECT COLUMN_NAME AS name, DATA_TYPE AS type, COLUMN_TYPE AS full_type,
                        IS_NULLABLE='YES' AS nullable,
                        COLUMN_DEFAULT AS col_default,
                        EXTRA LIKE '%auto_increment%' AS is_identity
                    FROM information_schema.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE() AND LOWER(TABLE_NAME) = LOWER(:t)
                    ORDER BY ORDINAL_POSITION";
            $rows = $db->fetchAll($sql, [':t'=>$phys]) ?? [];
            if ($rows) {
                self::dbg('columns(%s): information_schema OK (%d cols)', $table, count($rows));
                if ($useCache) { $cache[$keyPhys] = $rows; }
                return $rows;
            }

            // nic v I_S → zkontroluj skutečnou existenci tabulky (ať nevoláme SHOW na neexistující)
            $curDb = (string)($db->fetchOne('SELECT DATABASE()') ?? '');
            $existsTable = (int)$db->fetchOne(
                "SELECT COUNT(*) FROM information_schema.TABLES
                WHERE TABLE_SCHEMA=DATABASE() AND LOWER(TABLE_NAME)=LOWER(:t)",
                [':t'=>$phys]
            );

            if ($existsTable > 0) {
                // fallback: SHOW FULL COLUMNS (table)
                try {
                    $fallback = $db->fetchAll('SHOW FULL COLUMNS FROM ' . $db->quoteIdent($phys)) ?? [];
                    $norm = [];
                    foreach ($fallback as $r) {
                        $norm[] = [
                            'name'        => (string)$r['Field'],
                            'type'        => strtolower(preg_replace('/\(.*/', '', (string)$r['Type'])),
                            'full_type'   => (string)$r['Type'],
                            'nullable'    => (bool) (strtoupper((string)$r['Null']) === 'YES'),
                            'col_default' => $r['Default'] ?? null,
                            'is_identity' => (bool) (str_contains((string)$r['Extra'], 'auto_increment')),
                        ];
                    }
                    if ($norm) {
                        self::dbg('columns(%s): using SHOW FULL COLUMNS fallback (table, %d cols)', $table, count($norm));
                        if ($useCache) { $cache[$keyPhys] = $norm; }
                        return $norm;
                    }
                } catch (\Throwable $e) {
                    self::logDbError('SHOW FULL COLUMNS (table)', $e, true, "show-cols:table:{$phys}");
                }
            } else {
                self::dbg('columns(%s): information_schema empty and table does not exist in DB=%s → skipping table SHOW.',
                    $table, $curDb !== '' ? $curDb : '(NULL)');
            }

            // Fallback #2: contract view — pouze když je to skutečný view (contractView() vrátí odlišný název)
            $view = self::contractView($table);
            if ($view !== '' && strcasecmp($view, $table) !== 0) {
                $viewPhys = self::resolvePhysicalName($view);
                $isView = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.VIEWS
                    WHERE TABLE_SCHEMA=DATABASE() AND LOWER(TABLE_NAME)=LOWER(:t)",
                    [':t'=>$viewPhys]
                );
                if ($isView > 0) {
                    try {
                        $fallbackV = $db->fetchAll('SHOW FULL COLUMNS FROM ' . $db->quoteIdent($viewPhys)) ?? [];
                        $normV = [];
                        foreach ($fallbackV as $r) {
                            $normV[] = [
                                'name'        => (string)$r['Field'],
                                'type'        => strtolower(preg_replace('/\(.*/', '', (string)$r['Type'])),
                                'full_type'   => (string)$r['Type'],
                                'nullable'    => (bool) (strtoupper((string)$r['Null']) === 'YES'),
                                'col_default' => $r['Default'] ?? null,
                                'is_identity' => (bool) (str_contains((string)$r['Extra'], 'auto_increment')),
                            ];
                        }
                        if ($normV) {
                            self::dbg('columns(%s): using VIEW fallback (%s, %d cols)', $table, $viewPhys, count($normV));
                            if ($useCache) { $cache[$keyPhys] = $normV; }
                            return $normV;
                        }
                    } catch (\Throwable $e) {
                        self::logDbError("SHOW FULL COLUMNS (view {$viewPhys})", $e, true, "show-cols:view:{$viewPhys}");
                    }
                } else {
                    self::dbg('columns(%s): contract view candidate %s not present → skipping VIEW fallback.', $table, $viewPhys);
                }
            }

            // Vše vyčerpáno – žádný křik, protože to je očekávatelné před instalací modulů
            self::dbg('columns(%s): MySQL fallbacks exhausted, returning empty meta', $table);
            if ($useCache) { $cache[$keyPhys] = []; }
            return [];
        }

        // ===== Postgres beze změn =====
        $schema = self::pgSchema();
        $sql = "SELECT column_name AS name, data_type AS type, udt_name AS full_type,
                    is_nullable='YES' AS nullable,
                    column_default AS col_default,
                    (is_identity='YES' OR column_default ~ '^nextval\\(') AS is_identity
                FROM information_schema.columns
                WHERE table_schema=:schema AND table_name = :t
                ORDER BY ordinal_position";
        $rows = $db->fetchAll($sql, [':schema'=>$schema, ':t'=>$table]) ?? [];
        if (!$rows) {
            $found = $db->fetchOne(
                "SELECT table_schema
                FROM information_schema.tables
                WHERE LOWER(table_name) = LOWER(:t)
                LIMIT 1",
                [':t'=>$table]
            );
            self::warnOnce("pg-cols-miss:{$schema}:{$table}",
                'columns(%s): no rows in schema=%s; foundInOtherSchema=%s',
                $table, $schema, $found ? (string)$found : 'no'
            );
        } else {
            self::dbg('columns(%s): information_schema OK (schema=%s, %d cols)', $table, $schema, count($rows));
        }
        if ($useCache) { $cache[$key] = $rows; }
        return $rows;
    }

    /** Detaily cizích klíčů (seskupené podle constraintu). */
    public static function foreignKeysDetailed(string $table): array
    {
        [$dial] = self::dialect(); /** @var SqlDialect $dial */
        $db = Database::getInstance();

        self::dbg('foreignKeysDetailed(%s): dialect=%s', $table, $dial->value);

        if ($dial->isMysql()) {
            $phys = self::resolvePhysicalName($table);
            $sql = "SELECT k.CONSTRAINT_NAME AS name,
                           k.COLUMN_NAME AS col,
                           k.REFERENCED_TABLE_NAME AS ref_table,
                           k.REFERENCED_COLUMN_NAME AS ref_col,
                           (SELECT IS_NULLABLE='YES' FROM information_schema.COLUMNS c
                             WHERE c.TABLE_SCHEMA = DATABASE() AND LOWER(c.TABLE_NAME) = LOWER(k.TABLE_NAME) AND c.COLUMN_NAME = k.COLUMN_NAME) AS is_nullable
                    FROM information_schema.KEY_COLUMN_USAGE k
                    JOIN information_schema.REFERENTIAL_CONSTRAINTS r
                      ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
                    WHERE k.TABLE_SCHEMA = DATABASE() AND LOWER(k.TABLE_NAME) = LOWER(:t) AND k.REFERENCED_TABLE_NAME IS NOT NULL
                    ORDER BY k.POSITION_IN_UNIQUE_CONSTRAINT";
            $params = [':t'=>$phys];
        } else {
            $sql = "SELECT tc.constraint_name AS name,
                           kcu.column_name AS col,
                           ccu.table_name AS ref_table,
                           ccu.column_name AS ref_col,
                           (SELECT is_nullable='YES' FROM information_schema.columns c
                             WHERE c.table_schema=:schema AND c.table_name = tc.table_name AND c.column_name = kcu.column_name) AS is_nullable
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu
                      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
                    JOIN information_schema.constraint_column_usage ccu
                      ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
                    WHERE tc.table_schema = :schema AND tc.table_name = :t AND tc.constraint_type='FOREIGN KEY'
                    ORDER BY kcu.ordinal_position";
            $params = [':schema'=>self::pgSchema(), ':t'=>$table];
        }

        $rows = $db->fetchAll($sql, $params) ?? [];
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
        self::dbg('foreignKeysDetailed(%s): found %d constraints', $table, count($grp));
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
                if ($cols) {
                    $cols = array_values(array_map('strval', $cols));
                    self::dbg('allowedColumns(%s): from Definitions (%d)', $table, count($cols));
                    return $cols;
                }
            }
        } catch (\Throwable $e) {
            self::dbg('allowedColumns(%s): Definitions exception: %s', $table, $e->getMessage());
        }
        $cols = array_map(fn($c)=>(string)$c['name'], self::columns($table));
        self::dbg('allowedColumns(%s): from information_schema (%d)', $table, count($cols));
        return $cols;
    }

    /** Unikátní klíče ze schématu (information_schema) – včetně PK. */
    public static function uniqueKeysFromSchema(string $table): array
    {
        [$dial] = self::dialect(); /** @var SqlDialect $dial */
        $db = Database::getInstance();

        if ($dial->isMysql()) {
            $phys = self::resolvePhysicalName($table);
            $sql = "SELECT tc.CONSTRAINT_NAME AS name, kcu.COLUMN_NAME AS col, kcu.ORDINAL_POSITION AS pos
                    FROM information_schema.TABLE_CONSTRAINTS tc
                    JOIN information_schema.KEY_COLUMN_USAGE kcu
                      ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
                     AND tc.TABLE_SCHEMA   = kcu.TABLE_SCHEMA
                     AND tc.TABLE_NAME     = kcu.TABLE_NAME
                    WHERE tc.TABLE_SCHEMA = DATABASE()
                      AND LOWER(tc.TABLE_NAME) = LOWER(:t)
                      AND tc.CONSTRAINT_TYPE IN ('UNIQUE','PRIMARY KEY')
                    ORDER BY tc.CONSTRAINT_NAME, kcu.ORDINAL_POSITION";
            $params = [':t'=>$phys];
        } else {
            $sql = "SELECT tc.constraint_name AS name, kcu.column_name AS col, kcu.ordinal_position AS pos
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu
                      ON tc.constraint_name = kcu.constraint_name
                     AND tc.table_schema   = kcu.table_schema
                     AND tc.table_name     = kcu.table_name
                    WHERE tc.table_schema = :schema
                    AND tc.table_name   = :t
                    AND tc.constraint_type IN ('UNIQUE','PRIMARY KEY')
                    ORDER BY tc.constraint_name, kcu.ordinal_position";
            $params = [':schema'=>self::pgSchema(), ':t'=>$table];
        }

        $rows = $db->fetchAll($sql, $params) ?? [];
        $grp = [];
        foreach ($rows as $r) {
            $n = (string)$r['name'];
            $grp[$n] ??= [];
            $grp[$n][] = (string)$r['col'];
        }
        $out = array_values(array_map(fn($cols)=>array_values($cols), $grp));
        self::dbg('uniqueKeysFromSchema(%s): %d keys', $table, count($out));
        return $out;
    }

    /** Unikátní klíče z Definitions (mohou být prázdné). */
    public static function uniqueKeys(string $table): array
    {
        try {
            $defs = self::definitionsFor($table);
            if (class_exists($defs) && method_exists($defs, 'uniqueKeys')) {
                $uk = (array)$defs::uniqueKeys();
                self::dbg('uniqueKeys(%s): from Definitions (%d)', $table, count($uk));
                return $uk;
            }
        } catch (\Throwable $e) {
            self::dbg('uniqueKeys(%s): Definitions exception: %s', $table, $e->getMessage());
        }
        return [];
    }

    /** Definitions ∪ Schema, odfiltrované na povolené sloupce (repo je propustí). */
    public static function resolvedUniqueKeys(string $table): array
    {
        $allowed = array_fill_keys(self::allowedColumns($table), true);

        $decl = [];
        foreach (self::uniqueKeys($table) as $uk) {
            $cols = array_values(array_filter(array_map('strval', (array)$uk)));
            if ($cols && !array_diff($cols, array_keys($allowed))) $decl[] = $cols;
        }
        $schema = [];
        foreach (self::uniqueKeysFromSchema($table) as $uk) {
            $cols = array_values(array_filter(array_map('strval', (array)$uk)));
            if ($cols && !array_diff($cols, array_keys($allowed))) $schema[] = $cols;
        }

        $seen = []; $out = [];
        $add = function(array $cols) use (&$seen,&$out) {
            $key = implode("\x1F", $cols);
            if (!isset($seen[$key])) { $seen[$key]=true; $out[]=$cols; }
        };
        foreach ($decl as $c)   $add($c);
        foreach ($schema as $c) $add($c);

        self::dbg('resolvedUniqueKeys(%s): %d keys (decl=%d, schema=%d)', $table, count($out), count($decl), count($schema));
        return $out;
    }

    /**
     * Vloží řádek přes repo a zkusí vrátit PK (row[pk] / lastInsertId / dohledání přes unique / další fallbacky).
     * @return array{pkCol:string,pk:mixed}|null
     */
    public static function insertAndReturnId(string $table, array $row): ?array
    {
        $repo  = self::repoFor($table);
        $pkCol = self::primaryKey($table);
        $db    = Database::getInstance();

        $allowedSet = array_fill_keys(self::allowedColumns($table), true);
        $rowUsed    = array_intersect_key($row, $allowedSet);

        // Pokud volající přinesl PK – rovnou ho vraťme.
        if (array_key_exists($pkCol, $rowUsed) && $rowUsed[$pkCol] !== null && $rowUsed[$pkCol] !== '') {
            self::dbg('insertAndReturnId(%s): PK provided in payload (%s) → insert + return', $table, $pkCol);
            $repo->insert($rowUsed);
            return ['pkCol'=>$pkCol, 'pk'=>$rowUsed[$pkCol]];
        }

        // 1) INSERT
        self::dbg('insertAndReturnId(%s): inserting payload keys=[%s]', $table, implode(',', array_keys($rowUsed)));
        $repo->insert($rowUsed);

        // 2) lastInsertId()
        try {
            $id = $db->lastInsertId();
            if ($id !== null && $id !== '') {
                $idStr = (string)$id;
                self::dbg('insertAndReturnId(%s): lastInsertId()=%s', $table, $idStr);
                if (ctype_digit($idStr)) $id = (int)$idStr;
                return ['pkCol'=>$pkCol, 'pk'=>$id];
            }
        } catch (\Throwable $e) {
            self::dbg('insertAndReturnId(%s): lastInsertId exception: %s', $table, $e->getMessage());
        }

        // 3) Dohledání přes unikáty nad TABULKOU
        $found = self::fetchPkByUniqueKey($table, $rowUsed, $pkCol);
        if ($found !== null) {
            self::dbg('insertAndReturnId(%s): found via unique key → %s', $table, (string)$found);
            return ['pkCol'=>$pkCol, 'pk'=>$found];
        }

        // 4) Plný row-match
        $found = self::fetchPkByRowMatch($table, $rowUsed, $pkCol);
        if ($found !== null) {
            self::dbg('insertAndReturnId(%s): found via row-match → %s', $table, (string)$found);
            return ['pkCol'=>$pkCol, 'pk'=>$found];
        }

        // 5) PG fallback: currval(pg_get_serial_sequence('schema.table','pk'))
        try {
            if (self::isPg()) {
                $schema = self::pgSchema();
                $seqId = $db->fetchOne(
                    "SELECT currval(pg_get_serial_sequence(:t, :pk))",
                    [':t' => $schema . '.' . $table, ':pk' => $pkCol]
                );
                if ($seqId !== null && $seqId !== '') {
                    self::dbg('insertAndReturnId(%s): PG currval() fallback=%s', $table, (string)$seqId);
                    if (ctype_digit((string)$seqId)) $seqId = (int)$seqId;
                    return ['pkCol'=>$pkCol, 'pk'=>$seqId];
                }
            }
        } catch (\Throwable $e) {
            self::dbg('insertAndReturnId(%s): PG currval fallback failed: %s', $table, $e->getMessage());
        }

        // 6) Generic: poslední záznam dle PK DESC
        try {
            $pkExpr  = $db->quoteIdent($pkCol);
            $phys    = self::resolvePhysicalName($table);
            $tabExpr = $db->quoteIdent($phys);
            $lastId  = $db->fetchOne("SELECT {$pkExpr} FROM {$tabExpr} ORDER BY {$pkExpr} DESC LIMIT 1");
            if ($lastId !== null && $lastId !== '') {
                self::dbg('insertAndReturnId(%s): last PK DESC fallback=%s', $table, (string)$lastId);
                return ['pkCol'=>$pkCol, 'pk'=>$lastId];
            }
        } catch (\Throwable $e) {
            self::dbg('insertAndReturnId(%s): last PK DESC fallback failed: %s', $table, $e->getMessage());
        }

        self::warn('insertAndReturnId(%s): could not determine PK after insert (payload keys=[%s])', $table, implode(',', array_keys($rowUsed)));
        return null;
    }

    /** Dohledá PK podle prvního splnitelného unique key (všechny jeho sloupce jsou v $row). */
    public static function fetchPkByUniqueKey(string $table, array $row, string $pkCol = 'id'): mixed
    {
        $db = Database::getInstance();
        $pkExpr  = $db->quoteIdent($pkCol);
        $phys    = self::resolvePhysicalName($table);
        $tabExpr = $db->quoteIdent($phys);

        foreach (self::resolvedUniqueKeys($table) as $cols) {
            if (!$cols) continue;

            $present = true; $w = []; $p = [];
            foreach ($cols as $c) {
                if (!array_key_exists($c, $row) || $row[$c] === null) { $present = false; break; }
                $w[] = $db->quoteIdent($c) . ' = :' . $c;
                $p[':'.$c] = $row[$c];
            }
            if (!$present) continue;

            $sql = "SELECT {$pkExpr} FROM {$tabExpr} WHERE " . implode(' AND ', $w) . " LIMIT 1";
            $id  = $db->fetchOne($sql, $p);
            if ($id !== null) return $id;
        }

        // fallback – zkus plný row-match
        return self::fetchPkByRowMatch($table, $row, $pkCol);
    }

    /** Vytáhne PK dotazem přes “equal match” na všechny ne-NULL sloupce, které v tabulce existují. */
    private static function fetchPkByRowMatch(string $table, array $row, string $pkCol = 'id'): mixed
    {
        $db = Database::getInstance();
        $pkExpr  = $db->quoteIdent($pkCol);
        $phys    = self::resolvePhysicalName($table);
        $tabExpr = $db->quoteIdent($phys);

        $metaCols = array_fill_keys(array_map(fn($c) => (string)$c['name'], self::columns($table)), true);
        $conds = []; $params = [];
        foreach ($row as $k => $v) {
            if (!isset($metaCols[$k])) continue;
            if ($v === null) continue; // NULL rovnost by nic nenašla
            $conds[] = $db->quoteIdent($k) . ' = :' . $k;
            $params[':'.$k] = $v;
        }
        if (!$conds) return null;

        $sql = "SELECT {$pkExpr}
                FROM {$tabExpr}
                WHERE " . implode(' AND ', $conds) . "
                ORDER BY {$pkExpr} DESC
                LIMIT 1";
        return $db->fetchOne($sql, $params);
    }

    // -------------------- ENUM-like + REQUIRED-by-CHECK --------------------

    /** Vrátí mapu enum-like možností: [col => ['a','b',...]]. */
    public static function enumChoices(string $table): array
    {
        static $cache = [];
        $useCache = !self::cacheDisabled();
        $sfx = self::cacheSuffix();
        [$dial] = self::dialect(); /** @var SqlDialect $dial */

        if ($dial->isPg()) {
            $key = 'pg:' . self::pgSchema() . ':' . $table . ':' . $sfx;
            if ($useCache && isset($cache[$key])) return $cache[$key];
        } else {
            $phys = self::resolvePhysicalName($table);
            $key = 'mysql:' . $phys . ':' . $sfx;
            if ($useCache && isset($cache[$key])) return $cache[$key];
        }

        $db = Database::getInstance();
        $map = [];

        if ($dial->isPg()) {
            self::dbg('enumChoices(%s): PG mode', $table);
            // a) skutečné PG ENUM (včetně domén nad ENUM)
            $rows = $db->fetchAll(<<<'SQL'
                SELECT a.attname AS col, e.enumlabel AS val
                FROM pg_attribute a
                JOIN pg_class t   ON t.oid = a.attrelid
                JOIN pg_namespace n ON n.oid = t.relnamespace
                JOIN pg_type ty  ON ty.oid = a.atttypid
                JOIN pg_type bty ON bty.oid = COALESCE(NULLIF(ty.typbasetype,0), ty.oid)
                JOIN pg_enum e   ON e.enumtypid = bty.oid
                WHERE n.nspname=:schema AND t.relname = :t
                AND a.attnum > 0 AND NOT a.attisdropped
                ORDER BY e.enumsortorder
            SQL, [':schema'=>self::pgSchema(), ':t'=>$table]) ?? [];
            foreach ($rows as $r) { $map[(string)$r['col']][] = (string)$r['val']; }

            // b) CHECK constrainty
            $defs = $db->fetchAll(
                "SELECT pg_get_constraintdef(c.oid) AS def
                 FROM pg_constraint c
                 JOIN pg_class t ON t.oid = c.conrelid
                 JOIN pg_namespace n ON n.oid = t.relnamespace
                 WHERE c.contype='c' AND n.nspname=:schema AND t.relname = :t",
                [':schema'=>self::pgSchema(), ':t'=>$table]
            ) ?? [];

            foreach ($defs as $d) {
                $def = (string)$d['def'];

                if (preg_match('/CHECK\s*\(\s*"?(?<col>[a-z0-9_]+)"?(?:::text)?\s+IN\s*\(\s*(?<vals>.+?)\s*\)\s*\)/i', $def, $m)) {
                    $vals = array_map(fn($v)=>str_replace("''","'", trim($v, " '\"")), preg_split('/\s*,\s*/', $m['vals']));
                    if ($vals) { $map[$m['col']] = $map[$m['col']] ?? $vals; }
                }
                if (preg_match('/CHECK.*"?(?<col>[a-z0-9_]+)"?(?:::text)?\s*=\s*ANY\s*\(\s*\(?(?:ARRAY)?\[(?<vals>.+?)\]\)?/i', $def, $m)) {
                    $vals = array_map(fn($v)=>str_replace("''","'", trim(preg_replace('/::[a-z_]+$/i','', trim($v)), " '\"")), preg_split('/\s*,\s*/', $m['vals']));
                    if ($vals) { $map[$m['col']] = $map[$m['col']] ?? $vals; }
                }
                if (preg_match('/CHECK.*"?(?<col>[a-z0-9_]+)"?(?:::text)?\s*~\*?\s*\'\^\((?<vals>[^)]+)\)\$\'/i', $def, $m)) {
                    $vals = array_map('trim', explode('|', $m['vals']));
                    if ($vals) { $map[$m['col']] = $map[$m['col']] ?? $vals; }
                }
                if (preg_match('/CHECK\s*\((?<expr>.+)\)\s*$/i', $def, $mm)) {
                    $expr = $mm['expr'];
                    if (preg_match_all('/"?(?<col>[a-z0-9_]+)"?(?:::text)?\s*=\s*\'(?<val>(?:\'\'|[^\'])+)\'/i', $expr, $pairs, PREG_SET_ORDER)) {
                        $tmp = [];
                        foreach ($pairs as $p) { $tmp[$p['col']][] = str_replace("''", "'", $p['val']); }
                        foreach ($tmp as $c => $vals) {
                            $vals = array_values(array_unique($vals));
                            if (count($vals) >= 2) {
                                $map[$c] = $map[$c] ?? $vals;
                            }
                        }
                    }
                }
                if (preg_match('/CHECK.*(?:LOWER|UPPER)\s*\(\s*"?(?<col>[a-z0-9_]+)"?(?:::text)?\s*\)\s+IN\s*\(\s*(?<vals>.+?)\s*\)\s*\)?/i', $def, $m)) {
                    $vals = array_map(fn($v)=>str_replace("''","'", trim($v, " '\"")), preg_split('/\s*,\s*/', $m['vals']));
                    if ($vals) { $map[$m['col']] = $map[$m['col']] ?? $vals; }
                }
            }
        } else {
            self::dbg('enumChoices(%s): MySQL mode', $table);
            $phys = self::resolvePhysicalName($table);
            // (cache klíč i check už je připraven nahoře)
            $rows = $db->fetchAll(
                "SELECT column_name, column_type
                 FROM information_schema.columns
                 WHERE table_schema = DATABASE() AND LOWER(table_name) = LOWER(:t)",
                [':t'=>$phys]
            ) ?? [];
            foreach ($rows as $r) {
                $ct = strtolower((string)($r['column_type'] ?? ''));
                if (preg_match('/^enum\((.+)\)$/', $ct, $m) && preg_match_all("/'((?:\\\\'|[^'])*)'/", $m[1], $mm)) {
                    $vals = array_map(fn($s)=>str_replace("\\'", "'", $s), $mm[1]);
                    if ($vals) $map[(string)$r['column_name']] = $vals;
                }
            }
            foreach (self::mysqlCheckClausesForTable($table) as $exprRaw) {
                $expr = $exprRaw; // už samotná podmínka, bez "CHECK(...)"
                if (preg_match('/\b(?:LOWER|UPPER)\s*\(\s*`?(?<col>[A-Za-z0-9_]+)`?\s*\)\s+IN\s*\(\s*(?<vals>[^)]+)\)/i', $expr, $m)
                 || preg_match('/\b`?(?<col>[A-Za-z0-9_]+)`?\s+IN\s*\(\s*(?<vals>[^)]+)\)/i', $expr, $m)) {
                    $vals = [];
                    if (preg_match_all("/(?:_?[a-z0-9]+\s*)?'((?:\\\\'|[^'])*)'/i", $m['vals'], $mm)) {
                        $vals = array_map(fn($s)=>str_replace("\\'", "'", $s), $mm[1]);
                    }
                    if ($vals) {
                        $col = (string)$m['col'];
                        $map[$col] = $map[$col] ?? array_values(array_unique($vals));
                    }
                }
                if (preg_match('/\b`?(?<col>[A-Za-z0-9_]+)`?\s+(?:RLIKE|REGEXP)\s*\'\^\((?<alts>[^)]+)\)\$\'/i', $expr, $m)) {
                    $vals = array_values(array_filter(array_map('trim', explode('|', $m['alts'])), fn($v)=>$v!==''));
                    if ($vals) {
                        $col = (string)$m['col'];
                        $map[$col] = $map[$col] ?? $vals;
                    }
                }
            }
        }

        foreach ($map as $c => $vals) { $map[$c] = array_values(array_unique($vals)); }
        self::dbg('enumChoices(%s): %d columns with choices', $table, count($map));
        if ($useCache) { $cache[$key] = $map; }
        return $map;
    }

    /** Povinné sloupce podle CHECK (viz RowFactory). */
    public static function requiredByCheck(string $table): array
    {
        static $cache = [];
        $useCache = !self::cacheDisabled();
        $sfx = self::cacheSuffix();
        [$dial] = self::dialect(); /** @var SqlDialect $dial */

        if ($dial->isPg()) {
            $key = 'pg:' . self::pgSchema() . ':' . $table . ':' . $sfx;
            if ($useCache && isset($cache[$key])) return $cache[$key];
        } else {
            $phys = self::resolvePhysicalName($table);
            $key = 'mysql:' . $phys . ':' . $sfx;
            if ($useCache && isset($cache[$key])) return $cache[$key];
        }

        $db = Database::getInstance();
        $req = [];

        if ($dial->isPg()) {
            $rows = $db->fetchAll(
                "SELECT pg_get_constraintdef(c.oid) AS def
                 FROM pg_constraint c
                 JOIN pg_class t ON t.oid = c.conrelid
                 JOIN pg_namespace n ON n.oid = t.relnamespace
                 WHERE c.contype='c' AND n.nspname=:schema AND t.relname = :t",
                [':schema'=>self::pgSchema(), ':t'=>$table]
            ) ?? [];
            foreach ($rows as $r) {
                $def = (string)$r['def'];
                if (preg_match_all('/"(?<col>[a-z0-9_]+)"(?:::text)?\s+IS\s+NOT\s+NULL/i', $def, $m)) {
                    foreach ($m['col'] as $c) { $req[$c] = true; }
                }
                if (preg_match_all('/coalesce\s*\(\s*trim\s*\(\s*"(?<col>[a-z0-9_]+)"(?:::text)?\s*\)\s*,\s*\'\'\s*\)\s*(?:<>|!=)\s*\'\'/i', $def, $m2)) {
                    foreach ($m2['col'] as $c) { $req[$c] = true; }
                }
                if (preg_match_all('/(?:char_length|length)\s*\(\s*trim\s*\(\s*"(?<col>[a-z0-9_]+)"(?:::text)?\s*\)\s*\)\s*>\s*0/i', $def, $m3)) {
                    foreach ($m3['col'] as $c) { $req[$c] = true; }
                }
            }
        } else {
                $phys = self::resolvePhysicalName($table);
                // (cache klíč i check už je připraven nahoře)
            foreach (self::mysqlCheckClausesForTable($table) as $exprRaw) {
                $expr = $exprRaw;
                if (preg_match_all('/`(?<col>[A-Za-z0-9_]+)`\s+IS\s+NOT\s+NULL/i', $expr, $m)) {
                    foreach ($m['col'] as $c) { $req[$c] = true; }
                }
                if (preg_match_all('/coalesce\s*\(\s*trim\s*\(\s*`(?<col>[A-Za-z0-9_]+)`\s*\)\s*,\s*\'\'\s*\)\s*(?:<>|!=)\s*\'\'/i', $expr, $m2)) {
                    foreach ($m2['col'] as $c) { $req[$c] = true; }
                }
                if (preg_match_all('/(?:char_length|length)\s*\(\s*trim\s*\(\s*`(?<col>[A-Za-z0-9_]+)`\s*\)\s*\)\s*>\s*0/i', $expr, $m3)) {
                    foreach ($m3['col'] as $c) { $req[$c] = true; }
                }
                if (preg_match_all('/nullif\s*\(\s*trim\s*\(\s*`(?<col>[A-Za-z0-9_]+)`\s*\)\s*,\s*\'\'\s*\)\s+IS\s+NOT\s+NULL/i', $expr, $m4)) {
                    foreach ($m4['col'] as $c) { $req[$c] = true; }
                }
                if (preg_match_all('/trim\s*\(\s*`(?<col>[A-Za-z0-9_]+)`\s*\)\s*(?:<>|!=)\s*\'\'/i', $expr, $m5)) {
                    foreach ($m5['col'] as $c) { $req[$c] = true; }
                }
                if (preg_match_all('/`(?<col>[A-Za-z0-9_]+)`\s*(?:<>|!=)\s*\'\'/i', $expr, $m6)) {
                    foreach ($m6['col'] as $c) { $req[$c] = true; }
                }
            }
        }

        self::dbg('requiredByCheck(%s): %d required-by-check columns', $table, count($req));
        if ($useCache) { $cache[$key] = $req; }
        return $req;
    }

    // === PG coercions & FK smoke helper ==========================================================

    /**
     * Upraví sample řádek tak, aby PG nepadal na type/check/identity.
     * - vynechá identity PK (např. id)
     * - pro sloupce typu type/status/channel/mode/event/level zkusí nasadit hodnotu z CHECK/ENUM
     * - numerika převede na čísla
     * - datum/čas dá do platného stringu (dle typu)
     *
     * Loguje přes BC_DEBUG.
     */
   public static function coerceForPg(string $table, array $row): array
    {
        if (!self::isPg()) {
            return $row; // MySQL nic neupravujeme
        }

        $cols = self::columns($table);
        if (!$cols) { return $row; }

        // index meta podle názvů
        $meta = [];
        foreach ($cols as $c) {
           $name = (string)$c['name'];
            $meta[$name] = [
                'type'        => strtolower((string)$c['type']),
                'full_type'   => strtolower((string)($c['full_type'] ?? (string)$c['type'])),
                'is_identity' => (bool)($c['is_identity'] ?? false),
                'default'     => $c['col_default'] ?? null,
            ];
        }

        // id (identity) neposílat
        if (isset($row['id']) && isset($meta['id']) && $meta['id']['is_identity']) {
            self::dbg('coerceForPg(%s): unset identity id', $table);
            unset($row['id']);
        }
        // mapa enum-like voleb z PG (ENUM/DOMAIN + CHECK)
        $enumMap = self::enumChoices($table); // [col=>['a','b',...]]
        $enumMapLc = array_change_key_case($enumMap, CASE_LOWER);

        foreach ($row as $k => $v) {
            if (!isset($meta[$k])) { continue; }
            $type = $meta[$k]['type'];
            $kLc  = strtolower($k);

            // boolean → true/false
            if (preg_match('/\bbool/i', $type)) {
                if (!is_bool($v)) {
                    $s = strtolower((string)$v);
                    if (in_array($s, ['t','true','yes','y','1'], true)) {
                        $row[$k] = true;
                    } elseif (in_array($s, ['f','false','no','n','0'], true)) {
                        $row[$k] = false;
                    } else {
                        $row[$k] = false;
                    }
                }
                self::dbg('coerceForPg(%s): %s -> boolean %s', $table, $k, $row[$k] ? 'true' : 'false');
                continue;
            }

            // json/jsonb → validní JSON string
            if (str_contains($type, 'json')) {
                if (is_array($v) || is_object($v)) {
                    $row[$k] = json_encode($v, JSON_UNESCAPED_UNICODE);
                } elseif (!is_string($v) || $v === '') {
                    $row[$k] = '{}';
                } else {
                    $tmp = json_decode($v, true);
                    if ($tmp === null && json_last_error() !== JSON_ERROR_NONE) {
                        $row[$k] = '{}';
                    }
                }
                self::dbg('coerceForPg(%s): %s -> json %s', $table, $k, (string)$row[$k]);
                continue;
            }

            // enumy / „typové“ sloupce → doplň první povolenou hodnotu, pokud hodnota není mezi povolenými
            if (preg_match('/(^|_)(type|status|channel|mode|event|level)$/i', $k)) {
                $choices = $enumMap[$k] ?? $enumMapLc[$kLc] ?? null;
                if ($choices && !in_array((string)$v, array_map('strval', $choices), true)) {
                    self::dbg("coerceForPg(%s): %s coerced to '%s' from enum-like", $table, $k, (string)$choices[0]);
                    $row[$k] = (string)$choices[0];
                    continue;
                }
            }

            // čísla → čísla (PG kontroluje typy přísněji)
            if (preg_match('/int|numeric|decimal|double|real|smallint|bigint/i', $type)) {
                if (!is_int($v) && !is_float($v)) {
                    $row[$k] = is_numeric($v) ? 0 + $v : 0;
                    self::dbg('coerceForPg(%s): %s -> numeric %s', $table, $k, (string)$row[$k]);
                    continue;
                }
            }

            // datum/čas → validní string dle typu
            if (preg_match('/date|time/i', $type) && !is_string($v)) {
                $now = new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
                $isDate = stripos($type, 'date') !== false;
                $isTime = stripos($type, 'time') !== false;
                $fmt = ($isDate && !$isTime) ? 'Y-m-d' : (($isTime && !$isDate) ? 'H:i:s' : 'Y-m-d H:i:s');
                $row[$k] = $now->format($fmt);
                self::dbg('coerceForPg(%s): %s -> datetime %s', $table, $k, $row[$k]);
                continue;
            }
        }

        return $row;
    }

    /**
     * Má tabulka aspoň jeden NOT NULL FK sloupec? (rychlé PG smoke testy — můžeš je přeskakovat)
     * Loguje přes BC_DEBUG.
     */
    public static function hasHardFks(string $table): bool
    {
        $list = self::foreignKeysDetailed($table);
        foreach ($list as $fk) {
            foreach ($fk['nullable'] as $isNullable) {
                if ($isNullable === false) {
                    self::dbg('hasHardFks(%s): %s has NOT NULL', $table, $fk['name'] ?? '(fk)');
                    return true;
                }
            }
        }
        self::dbg('hasHardFks(%s): none', $table);
        return false;
    }

    /**
     * Rychlý bezpečnostní profil tabulky pro generování vzorků přes Repository.
     * - flagne REQUIRED multi-column FK (nebudeme hádat kompozity),
     * - flagne NOT NULL FK,
     * - flagne required-by-check/enum-like sloupce, které repo nepropouští a nemají DEFAULT.
     * @return array{unsafe:bool,reasons:array<int,string>}
     */
    public static function safetyProfile(string $table): array
    {
        $reasons = [];

        $byName = [];
        foreach (self::columns($table) as $c) {
            $byName[strtolower((string)$c['name'])] = $c;
        }

        // (1) multi-column FK, kde jsou VŠECHNY sloupce NOT NULL
        foreach (self::foreignKeysDetailed($table) as $fk) {
            $cols = (array)$fk['cols'];
            if (count($cols) >= 2) {
                $allRequired = true;
                foreach ($cols as $lc) {
                    $m = $byName[strtolower($lc)] ?? null;
                    if (!$m) { $allRequired = false; break; }
                    $notNull = !(bool)($m['nullable'] ?? true);
                    $hasDef  = array_key_exists('col_default', $m) && $m['col_default'] !== null;
                    if (!($notNull && !$hasDef)) { $allRequired = false; break; }
                }
                if ($allRequired) {
                    $reasons[] = 'required multi-column FK (' . implode(',', $cols) . ')';
                }
            }
        }

        // (2) obecně NOT NULL FKs
        if (self::hasHardFks($table)) {
            $reasons[] = 'has NOT NULL foreign keys';
        }

        // (3) required-by-check / enum-like nepovolené repo whitelistem bez DEFAULT
        $allowed      = self::allowedColumns($table);
        $allowedSet   = array_fill_keys($allowed, true);
        $allowedSetLc = array_fill_keys(array_map('strtolower', $allowed), true);
        $reqByCheck   = self::requiredByCheck($table);
        $enumMap      = self::enumChoices($table);
        $enumMapLc    = array_change_key_case($enumMap, CASE_LOWER);

        foreach ($reqByCheck as $colLc => $_) {
            $meta = $byName[$colLc] ?? null;
            if (!$meta) continue;
            $hasDefault = array_key_exists('col_default', $meta) && $meta['col_default'] !== null;
            $allowedCol = isset($allowedSet[$meta['name'] ?? '']) || isset($allowedSetLc[$colLc]);
            if (!$allowedCol && !$hasDefault) {
                $reasons[] = "required column '$colLc' not allowed by repository and no DEFAULT";
            }
        }

        foreach ($enumMapLc as $colLc => $choices) {
            $meta = $byName[$colLc] ?? null;
            if (!$meta) continue;
            $notNull    = !(bool)($meta['nullable'] ?? true);
            $hasDefault = array_key_exists('col_default', $meta) && $meta['col_default'] !== null;
            $allowedCol = isset($allowedSet[$meta['name'] ?? '']) || isset($allowedSetLc[$colLc]);
            if ($notNull && !$allowedCol && !$hasDefault) {
                $reasons[] = "enum-like required column '$colLc' not allowed by repository and no DEFAULT";
            }
        }

        return ['unsafe' => (bool)$reasons, 'reasons' => $reasons];
    }

    public static function isInsertSafe(string $table): bool
    {
        return !self::safetyProfile($table)['unsafe'];
    }

    /** @return array<string,array{reasons:array<int,string>}> */
    public static function listUnsafeTables(): array
    {
        self::ensureRegistry();
        $out = [];
        foreach (array_keys(self::$registry) as $t) {
            $p = self::safetyProfile($t);
            if ($p['unsafe']) $out[$t] = ['reasons' => $p['reasons']];
        }
        return $out;
    }

    /** Jednorázový rentgen views a kontraktů (aktivní jen s BC_TRACE_VIEWS). */
    private static function traceViewsSnapshot(): void
    {
        $db = Database::getInstance();
        [$dial] = self::dialect();

        if ($dial->isPg()) {
            $schema = self::pgSchema();
            $rows = $db->fetchAll(
                "SELECT table_name AS name FROM information_schema.views
                 WHERE table_schema=:s ORDER BY table_name", [':s'=>$schema]
            ) ?? [];
            $all = array_map(fn($r)=>(string)$r['name'], $rows);
            self::tv('[SNAP] PG schema=%s views.count=%d -> %s', $schema, count($all), implode(', ', $all));
        } else {
            $curDb = (string)($db->fetchOne('SELECT DATABASE()') ?? '');
            $rows = $db->fetchAll(
                "SELECT TABLE_NAME AS name FROM information_schema.VIEWS
                 WHERE TABLE_SCHEMA=DATABASE() ORDER BY TABLE_NAME"
            ) ?? [];
            $all = array_map(fn($r)=>(string)$r['name'], $rows);
            self::tv('[SNAP] MySQL db=%s views.count=%d -> %s', $curDb !== '' ? $curDb : '(NULL)', count($all), implode(', ', $all));
        }

        // Mapování kontraktů u všech registrovaných tabulek
        foreach (array_keys(self::$registry) as $t) {
            $cv = self::contractView($t);
            $physCv = self::resolvePhysicalName($cv);

            if ($dial->isPg()) {
                $isView = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.views
                     WHERE table_schema=:s AND LOWER(table_name)=LOWER(:t)",
                    [':s'=>self::pgSchema(), ':t'=>$physCv]
                );
            } else {
                $isView = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.VIEWS
                     WHERE TABLE_SCHEMA=DATABASE() AND LOWER(TABLE_NAME)=LOWER(:t)",
                    [':t'=>$physCv]
                );
            }
            $kind = $isView > 0 ? 'view' : 'table';
            self::tv('[MAP] table=%s -> contractView=%s (phys=%s kind=%s)', $t, $cv, $physCv, $kind);

            // Detekce „duplikátů“ názvů (typicky prefix + vw_<table>) – jen MySQL
            if (!$dial->isPg()) {
                $cand = 'vw_' . $t;
                $rows = $db->fetchAll(
                    "SELECT TABLE_NAME AS name FROM information_schema.VIEWS
                     WHERE TABLE_SCHEMA=DATABASE()
                     AND LOWER(TABLE_NAME) LIKE LOWER(CONCAT('%', :cand))
                     ORDER BY LENGTH(TABLE_NAME)",
                    [':cand'=>$cand]
                ) ?? [];
                $dups = array_map(fn($r)=>(string)$r['name'], $rows);
                if (count($dups) > 1) {
                    self::tv('[DUP] table=%s cand=%s -> found views: %s', $t, $cand, implode(', ', $dups));
                }
            }
        }

        // Kontrola očekávaných computed sloupců (jen MySQL)
        if (!$dial->isPg()) {
            $strictRaw = $_ENV['BC_STRICT_TRACE_VIEWS'] ?? getenv('BC_STRICT_TRACE_VIEWS') ?? '';
            $strict = ($strictRaw === '1' || strcasecmp((string)$strictRaw, 'true') === 0);

            if (!$strict) {
                self::tv('[CHECK] Skipping computed-columns check (set BC_STRICT_TRACE_VIEWS=1 to enable).');
            } else {
                $expect = [
                    'vw_sessions'             => ['is_active'],
                    'vw_coupons'              => ['is_current'],
                    'vw_idempotency_keys'     => ['is_expired'],
                    'vw_order_item_downloads' => ['uses_left','is_valid'],
                    'vw_system_errors'        => ['ip_bin_hex','ip_pretty'],
                    'vw_users'                => ['email_hash_hex','last_login_ip_hash_hex'],
                ];
                foreach ($expect as $view => $cols) {
                    $exists = (int)$db->fetchOne(
                        "SELECT COUNT(*) FROM information_schema.VIEWS
                        WHERE TABLE_SCHEMA=DATABASE() AND LOWER(TABLE_NAME)=LOWER(:v)",
                        [':v'=>$view]
                    );
                    if ($exists === 0) { self::tv('[CHECK] %s: view missing', $view); continue; }

                    $rows = $db->fetchAll(
                        "SELECT LOWER(COLUMN_NAME) AS col FROM information_schema.COLUMNS
                        WHERE TABLE_SCHEMA=DATABASE() AND LOWER(TABLE_NAME)=LOWER(:v)",
                        [':v'=>$view]
                    ) ?? [];
                    $have = array_fill_keys(array_map(fn($r)=>(string)$r['col'], $rows), true);
                    $miss = [];
                    foreach ($cols as $c) if (!isset($have[strtolower($c)])) $miss[] = $c;

                    if ($miss) {
                        self::tv('[CHECK] %s: MISSING columns: %s', $view, implode(',', $miss));
                        try {
                            $scv = $db->fetchAll('SHOW CREATE VIEW ' . $db->quoteIdent($view)) ?? [];
                            $ddl = $scv[0]['Create View'] ?? ($scv[0]['Create View'] ?? '');
                            if (is_string($ddl) && $ddl !== '') {
                                self::tv('[CHECK] SHOW CREATE VIEW %s: %s', $view, $ddl);
                            }
                        } catch (\Throwable $e) {
                            self::tv('[CHECK] SHOW CREATE VIEW %s failed: %s', $view, $e->getMessage());
                        }
                    } else {
                        self::tv('[CHECK] %s: OK', $view);
                    }
                }
            }
        }
    }

    // -------------------- INTERNALS / HELPERS --------------------

    private static function envTrue(string $name): bool {
        $v = $_ENV[$name] ?? getenv($name) ?? '';
        return $v === '1' || strcasecmp((string)$v, 'true') === 0;
    }

    /** Najde <repo>/schema vedle /src modulu (best-effort, stačí pro testy). */
    private static function moduleSchemaDir(ModuleInterface $m): ?string {
        try {
            $file = (new \ReflectionClass($m))->getFileName() ?: '';
        } catch (\Throwable) {
            return null;
        }
        if ($file === '') return null;
        $dir = dirname($file);
        // šplhej nahoru a hledej souběžné 'src' a 'schema'
        while ($dir && $dir !== DIRECTORY_SEPARATOR) {
            $cand = $dir . DIRECTORY_SEPARATOR . 'schema';
            if (is_dir($cand) && is_dir($dir . DIRECTORY_SEPARATOR . 'src')) {
                return realpath($cand) ?: $cand;
            }
            $parent = dirname($dir);
            if ($parent === $dir) break;
            $dir = $parent;
        }
        // fallback ../schema
        $fallback = dirname($file) . DIRECTORY_SEPARATOR . '..' . DIRECTORY_SEPARATOR . 'schema';
        return is_dir($fallback) ? (realpath($fallback) ?: $fallback) : null;
    }

    /** Vyparsuje názvy view z 040_views.<dial>.sql pro daný modul. */
    private static function declaredViewsForModule(ModuleInterface $m, SqlDialect $dialect): array {
        $schemaDir = self::moduleSchemaDir($m);
        if (!$schemaDir) return [];
        $d = $dialect->isMysql() ? 'mysql' : 'postgres';
        $path = $schemaDir . DIRECTORY_SEPARATOR . "040_views.$d.sql";
        if (!is_file($path)) return [];
        $sql = (string)@file_get_contents($path);
        if ($sql === '') return [];
        // stejné jádro regexu jako v Installeru
        if (preg_match_all(
            '~CREATE\s+(?:OR\s+REPLACE\s+)?'
        . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*'
        . 'VIEW\s+(`?"?)([A-Za-z0-9_]+)\1\s+AS~i',
            $sql, $m1
        )) {
            // case-insensitive set, vracej hezké názvy
            $set = [];
            foreach ($m1[2] as $v) { $set[strtolower((string)$v)] = (string)$v; }
            return array_values($set);
        }
        return [];
    }

    private static function verifyViewsOrRepair(array $mods, Installer $installer, SqlDialect $dialect): void {
        $db = Database::getInstance();
        $strict = self::envTrue('BC_HARNESS_STRICT_VIEWS');

        $missing = [];
        foreach ($mods as $m) {
            $decl = self::declaredViewsForModule($m, $dialect);
            if (!$decl) continue; // modul žádná view nedefinuje
            foreach ($decl as $name) {
                if (self::isMysql()) {
                    $cnt = (int)$db->fetchOne(
                        "SELECT COUNT(*) FROM information_schema.VIEWS
                        WHERE TABLE_SCHEMA=DATABASE() AND LOWER(TABLE_NAME)=LOWER(:v)", [':v'=>$name]
                    );
                } else {
                    $cnt = (int)$db->fetchOne(
                        "SELECT COUNT(*) FROM information_schema.views
                        WHERE table_schema = ANY (current_schemas(true)) AND LOWER(table_name)=LOWER(:v)", [':v'=>$name]
                    );
                }
                if ($cnt > 0) continue;

                // první pokus o opravu: přehraj jen tento modul
                self::dbg('verifyViews: %s missing -> replay module %s', $name, $m->name());
                $installer->installOrUpgrade($m);

                // re-check
                if (self::isMysql()) {
                    $cnt = (int)$db->fetchOne(
                        "SELECT COUNT(*) FROM information_schema.VIEWS
                        WHERE TABLE_SCHEMA=DATABASE() AND LOWER(TABLE_NAME)=LOWER(:v)", [':v'=>$name]
                    );
                } else {
                    $cnt = (int)$db->fetchOne(
                        "SELECT COUNT(*) FROM information_schema.views
                        WHERE table_schema = ANY (current_schemas(true)) AND LOWER(table_name)=LOWER(:v)", [':v'=>$name]
                    );
                }
                if ($cnt === 0) { $missing[] = $name; }
            }
        }

        if ($missing) {
            $msg = 'Missing contract views after install: ' . implode(', ', $missing);
            if ($strict) {
                throw new \RuntimeException($msg);
            }
            self::warn('verifyViews: %s', $msg);
        }
    }

    /**
     * Dialect + driver string.
     * @return array{0: SqlDialect, 1: string}
     */
    public static function dialect(): array
    {
        $driver  = (string)Database::getInstance()->getPdo()->getAttribute(\PDO::ATTR_DRIVER_NAME);
        return [$driver === 'mysql' ? SqlDialect::mysql : SqlDialect::postgres, $driver];
    }

    /** Rychlá kontrola: běžíme na Postgresu? */
    public static function isPg(): bool
    {
        [$dial] = self::dialect(); /** @var SqlDialect $dial */
        return $dial->isPg();
    }

    /** Rychlá kontrola: běžíme na MySQL? */
    public static function isMysql(): bool
    {
        [$dial] = self::dialect(); /** @var SqlDialect $dial */
        return $dial->isMysql();
    }

    /** Aktuální PG schema (fallback 'public'); pro MySQL se ignoruje. */
    private static function pgSchema(): string
    {
        $s = getenv('BC_PG_SCHEMA');
        $schema = ($s !== false && $s !== '') ? $s : 'public';
        return $schema;
    }

    /** MySQL – vrátí seznam CHECK_CLAUSE výrazů pro danou tabulku (pro parsování enum-like/required). */
    private static function mysqlCheckClausesForTable(string $table): array
    {
        static $cache = [];
        $useCache = !self::cacheDisabled();
        $sfx = self::cacheSuffix();
        if (self::isPg()) return [];

        $db = Database::getInstance();
        $phys = self::resolvePhysicalName($table);
        $keyPhys = 'mysql:' . $phys . ':' . $sfx;
        if ($useCache && isset($cache[$keyPhys])) return $cache[$keyPhys];

        try {
            $rows = $db->fetchAll(
                "SELECT cc.CHECK_CLAUSE AS expr
                 FROM information_schema.TABLE_CONSTRAINTS tc
                 JOIN information_schema.CHECK_CONSTRAINTS cc
                   ON cc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
                  AND cc.CONSTRAINT_NAME  = tc.CONSTRAINT_NAME
                 WHERE tc.CONSTRAINT_TYPE = 'CHECK'
                   AND tc.TABLE_SCHEMA     = DATABASE()
                   AND LOWER(tc.TABLE_NAME) = LOWER(:t)",
                [':t' => $phys]
            ) ?? [];
        } catch (\Throwable $e) {
            self::logDbError("mysqlCheckClausesForTable({$table})", $e, true, "checks:{$table}");
            $rows = [];
        }

        $out = [];
        foreach ($rows as $r) {
            $expr = (string)$r['expr'];
            if ($expr !== '') { $out[] = $expr; }
        }
        self::dbg('mysqlCheckClausesForTable(%s): %d checks', $table, count($out));
        if ($useCache) { $cache[$keyPhys] = $out; }
        return $out;
    }

    private static function resolvePhysicalName(string $logical): string
    {
        static $cache = [];

        $useCache = !self::cacheDisabled();
        $idx = strtolower($logical) . '|' . self::cacheSuffix();
        if ($useCache && isset($cache[$idx])) return $cache[$idx];

        // Postgres: žádné domýšlení – pracujeme se jménem tak, jak je (schema řeší jinde).
        if (self::isPg()) {
            if ($useCache) $cache[$idx] = $logical;
            return $logical;
        }

        // MySQL/MariaDB: jen striktní 1:1 shody, bez LIKE, bez suffix/prefix heuristik.
        $db = \BlackCat\Core\Database::getInstance();

        // 1) přesná shoda v TABLES
        $found = (string)($db->fetchOne(
            "SELECT TABLE_NAME FROM information_schema.TABLES
             WHERE TABLE_SCHEMA = DATABASE() AND LOWER(TABLE_NAME) = LOWER(:t) LIMIT 1",
            [':t' => $logical]
        ) ?? '');
        if ($found !== '') { if ($useCache) $cache[$idx] = $found; return $found; }

        // 2) přesná shoda ve VIEWS
        $found = (string)($db->fetchOne(
            "SELECT TABLE_NAME FROM information_schema.VIEWS
             WHERE TABLE_SCHEMA = DATABASE() AND LOWER(TABLE_NAME) = LOWER(:t) LIMIT 1",
            [':t' => $logical]
        ) ?? '');
        if ($found !== '') { if ($useCache) $cache[$idx] = $found; return $found; }

        // 3) nic nenalezeno → vrať logické jméno (žádné hádání).
        if ($useCache) $cache[$idx] = $logical;
        self::dbg('resolvePhysicalName: %s -> %s (no guess)', $logical, $logical);
        return $logical;
    }

    /** Logické -> fyzické jméno (MySQL prefix; na PG beze změny). */
    public static function physicalName(string $name): string
    {
        return self::resolvePhysicalName($name);
    }

    /**
     * Zkusí převést fyzické jméno (např. 'bc_users') zpět na logické (např. 'users').
     * Pokud už je to logické, vrátí originál.
     */
    public static function logicalFromPhysical(string $maybePhysical): string
    {
        self::ensureRegistry();

        // 1) přímá shoda na klíčích registru (case-insensitive)
        foreach (array_keys(self::$registry) as $t) {
            if (strcasecmp($t, $maybePhysical) === 0) return $t;
        }

        // 2) MySQL: porovnej přes fyzické jméno z resolvePhysicalName()
        if (self::isMysql()) {
            foreach (array_keys(self::$registry) as $t) {
                $phys = self::resolvePhysicalName($t);
                if (strcasecmp($phys, $maybePhysical) === 0) return $t;
            }
        }

        // 3) fallback – nic lepšího nevíme
        return $maybePhysical;
    }

    /** Vybuduje registr {table => ns/repo/defs/view} z dostupných modulů. */
    private static function buildRegistry(array $mods): void
    {
        self::$registry = [];
        foreach ($mods as $m) {
            if (!method_exists($m, 'table')) continue;

            $table  = (string)$m->table();
            $cls    = get_class($m); // …\Packages\X\XModule → základ …\Packages\X
            $nsBase = (string)preg_replace('~\\\[^\\\]+$~', '', $cls);
            $nsBase = (string)preg_replace('~Module$~', '', $nsBase);
            if (str_ends_with($nsBase, '\\')) $nsBase = substr($nsBase, 0, -1);

            $defs = $nsBase . '\\Definitions';

            // contract view (pokud jde vyčíst)
            $view = null;
            if (class_exists($defs) && method_exists($defs, 'contractView')) {
                try { $view = (string)$defs::contractView(); } catch (\Throwable $_) {}
            }

            $repoFqn = self::resolveRepoFqn($nsBase, $defs);

            self::$registry[$table] = [
                'ns'   => $nsBase,
                'repo' => $repoFqn,
                'defs' => $defs,
                'view' => $view,
            ];
            self::dbg('buildRegistry: table=%s ns=%s repo=%s defs=%s view=%s',
                $table, $nsBase, $repoFqn ?? '(null)', $defs, $view ?? '(null)'
            );
        }
    }

    /** Najde Repository FQN pro daný balík (nsBase = …\Packages\X). */
    private static function resolveRepoFqn(string $nsBase, string $defsFqn): ?string
    {
        if ($nsBase === '' || $defsFqn === '' || !class_exists($defsFqn)) return null;

        // 1) konvence: \Repository\{Entity}Repository, kde {Entity}=PascalCase(singular(Definitions::table()))
        try {
            $table = (string)$defsFqn::table(); // např. "users", "order_items"
        } catch (\Throwable) {
            $table = '';
        }
        if ($table !== '') {
            $entityPascal = self::toPascalCase(self::singularize($table));
            $cand = $nsBase . "\\Repository\\{$entityPascal}Repository";
            if (class_exists($cand)) return $cand;
        }

        // 2) fallback: proskenuj soubory …/packages/<Pkg>/src/Repository/*Repository.php
        $pkgPascal = basename(str_replace('\\', '/', $nsBase)); // "Users", "Orders", …
        $dir = realpath(__DIR__ . "/../../packages/{$pkgPascal}/src/Repository");
        if ($dir && is_dir($dir)) {
            foreach (glob($dir . '/*Repository.php') ?: [] as $file) {
                $base = basename($file, '.php');              // např. UserRepository
                $fqn  = $nsBase . "\\Repository\\{$base}";
                if (class_exists($fqn)) return $fqn;
                require_once $file;                            // dovyžádej
                if (class_exists($fqn)) return $fqn;
            }
        }

        return null;
    }

    /** velmi jednoduchá singulizace v souladu s generátorem */
    private static function singularize(string $word): string
    {
        if (preg_match('~ies$~i', $word))   return preg_replace('~ies$~i', 'y', $word);
        if (preg_match('~sses$~i', $word))  return preg_replace('~es$~i',  '',  $word);
        if (preg_match('~s$~i', $word) && !preg_match('~(news|status)$~i', $word)) {
            return substr($word, 0, -1);
        }
        return $word;
    }

    /** "order_items" → "OrderItems" */
    private static function toPascalCase(string $snakeOrKebab): string
    {
        $parts = preg_split('~[_\-]+~', $snakeOrKebab) ?: [];
        $parts = array_map(fn($p) => $p === '' ? $p : (mb_strtoupper(mb_substr($p,0,1)).mb_strtolower(mb_substr($p,1))), $parts);
        return implode('', $parts);
    }

    /** zamezí duplicitnímu bootstrapu v rámci procesu */
    private static bool $bootstrapped = false;

    private static function bootstrapOnce(): void
    {
        if (self::$bootstrapped) return;
        self::$bootstrapped = true;
        // nainstaluje/upgradeuje moduly + postaví registry
        self::ensureInstalled();
    }

    private static function ensureRegistry(): void
    {
        if (self::$registry) return;
        // NOVÉ: místo prostého discover/build vždy nejdřív zajistit instalaci
        self::bootstrapOnce();
        if (self::$registry) return; // ensureInstalled už registry postavil

        // (bezpečnostní fallback – běžet by nemělo, ale neuškodí)
        [$dial] = self::dialect();
        $mods = self::discoverModules($dial);
        self::buildRegistry($mods);
    }

    /** @param ModuleInterface[] $modules @return ModuleInterface[] */
    private static function toposort(array $modules): array
    {
        $byName = [];
        foreach ($modules as $m) { $byName[$m->name()] = $m; }

        $visited = $temp = [];
        $out = [];

        $visit = function (string $name) use (&$visit, &$visited, &$temp, &$out, $byName): void {
            if (isset($visited[$name])) return;
            if (isset($temp[$name])) throw new \RuntimeException("Dependency cycle detected at '$name'.");
            if (!isset($byName[$name])) { $visited[$name] = true; return; }

            $temp[$name] = true;
            foreach ($byName[$name]->dependencies() as $dep) { $visit($dep); }
            unset($temp[$name]);
            $visited[$name] = true;
            $out[] = $byName[$name];
        };

        foreach (array_keys($byName) as $n) { $visit($n); }
        self::dbg('toposort: modules=%d → sorted=%d', count($modules), count($out));
        return $out;
    }
}
