<?php
declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Database\Support\DdlGuard;

final class Installer
{
    private DdlGuard $ddlGuard;
    private bool $registryEnsured = false;
    /** už jednou ohlášené "views: skip" per modul v rámci instance */
    private array $viewsSkipNotified = [];
    /** sekvenční ID běhu pro přehledné logy */
    private int $runSeq = 0;
    private bool $debug; // ← přidaná interní vlajka
    // jemnější řízení verbóznosti
    private bool $traceSql = false;
    private bool $traceFiles = false;
    private bool $verbose = false;

    /** Odstraní SQL komentáře, ale ponechá vše ostatní (ALGORITHM, SECURITY, …) */
    private function stripSqlComments(string $sql): string
    {
        // Odstraň BOM a NBSP → aby detekce začátku řádku/whitespace fungovala spolehlivě
        if (strncmp($sql, "\xEF\xBB\xBF", 3) === 0) {
            $sql = substr($sql, 3);
        }
        $sql = str_replace("\xC2\xA0", ' ', $sql); // NBSP → mezera

        $out = '';
        $len = strlen($sql);
        $inSingle = $inDouble = $inBacktick = false;

        // Dialektové přepínače
        $isMysql = $this->dialect->isMysql();
        $isPg    = $this->dialect->isPg();

        for ($i = 0; $i < $len; $i++) {
            $ch   = $sql[$i];
            $next = $i + 1 < $len ? $sql[$i + 1] : '';
            $prev = $i > 0 ? $sql[$i - 1] : '';

            // přepínání stavů uvnitř stringů/identifikátorů
            if (!$inDouble && !$inBacktick && $ch === "'") {
                if (!$inSingle) { $inSingle = true; $out .= $ch; continue; }
                // konec single only pokud není backslash-escape ani dvojitý ''
                if ($next === "'") { $out .= "''"; $i++; continue; }
                if ($prev !== "\\") { $inSingle = false; $out .= $ch; continue; }
                $out .= $ch; continue;
            }
            if (!$inSingle && !$inBacktick && $ch === '"') {
                if (!$inDouble) { $inDouble = true; $out .= $ch; continue; }
                if ($next === '"') { $out .= '""'; $i++; continue; }
                if ($prev !== "\\") { $inDouble = false; $out .= $ch; continue; }
                $out .= $ch; continue;
            }
            if (!$inSingle && !$inDouble && $ch === '`') {
                if (!$inBacktick) { $inBacktick = true; $out .= $ch; continue; }
                if ($next === '`') { $out .= '``'; $i++; continue; }
                $inBacktick = false; $out .= $ch; continue;
            }

            // Mimo string/backtick: smaž blokové a řádkové komentáře
            if (!$inSingle && !$inDouble && !$inBacktick) {
                // /* ... */
                if ($ch === '/' && $next === '*') {
                    $end = strpos($sql, '*/', $i + 2);
                    if ($end === false) break;          // žádný konec → zahodit zbytek
                    $i = $end + 1;                       // posuň za */
                    continue;
                }

                // -- ...  (dialektově)
                if ($ch === '-' && $next === '-') {
                    $pre   = $i > 0 ? $sql[$i - 1] : "\n";
                    $after = ($i + 2 < $len) ? $sql[$i + 2] : ' ';
                    $startToken = ctype_space($pre); // '--' na začátku tokenu (začátek řádku/whitespace)

                    // MySQL/MariaDB: '--' je komentář jen pokud je za ním whitespace/řídicí znak
                    $mysqlOk = $isMysql && $startToken && (ctype_space($after) || ord($after) < 32);
                    // Postgres: '--' je komentář kdykoliv na začátku tokenu (mezera po '--' není nutná)
                    $pgOk    = $isPg && $startToken;

                    if ($mysqlOk || $pgOk) {
                        while ($i < $len && $sql[$i] !== "\n" && $sql[$i] !== "\r") { $i++; }
                        continue;
                    }
                }

                // # ... (jen MySQL/MariaDB; v PG by to rozbilo JSON operátory #>, #>> apod.)
                if ($isMysql && $ch === '#') {
                    $pre = $i > 0 ? $sql[$i - 1] : "\n";
                    if (ctype_space($pre)) {
                        while ($i < $len && $sql[$i] !== "\n" && $sql[$i] !== "\r") { $i++; }
                        continue;
                    }
                }
            }

            $out .= $ch;
        }

        return $out;
    }

    /** Vrátí cestu k <repo-root>/schema, tj. ke schématu vedle kořenového /src.
     *  Pokud není nalezeno, vrací rozumný fallback (../schema relativně k souboru modulu).
     */
    private function schemaDirBesideSrc(ModuleInterface $m): string
    {
        // 1) explicitní override přes env (užitečné v CI/Dockeru)
        $env = getenv('BC_SCHEMA_DIR');
        if ($env && is_dir($env)) {
            $r = realpath($env);
            return $r ?: $env;
        }

        // 2) zjisti cestu k souboru třídy modulu
        $file = (new \ReflectionClass($m))->getFileName() ?: '';
        $dir  = $file !== '' ? dirname($file) : getcwd();

        // 3) šplhej nahoru; na každé úrovni hledej SOUČASNÝ výskyt 'src' a 'schema'
        //    (tím zachytíme kořen projektu i když modul žije pod packages/*/src)
        while ($dir && $dir !== DIRECTORY_SEPARATOR) {
            $candSchema = $dir . DIRECTORY_SEPARATOR . 'schema';
            $candSrc    = $dir . DIRECTORY_SEPARATOR . 'src';
            if (is_dir($candSchema) && is_dir($candSrc)) {
                $resolved = realpath($candSchema);
                return $resolved ?: $candSchema;
            }
            $parent = dirname($dir);
            if ($parent === $dir) break;
            $dir = $parent;
        }

        // 4) poslední záchrana – nejbližší ../schema relativně k souboru modulu
        $fallback = dirname($file) . DIRECTORY_SEPARATOR . '..' . DIRECTORY_SEPARATOR . 'schema';
        $resolvedFallback = realpath($fallback);
        return ($resolvedFallback && is_dir($resolvedFallback)) ? $resolvedFallback : $fallback;
    }

    /** Rozseká skript na jednotlivé příkazy; ignoruje ; uvnitř stringů/identifikátorů */
    private function splitSqlStatements(string $sql): array
    {
        $out = [];
        $buf = '';
        $len = strlen($sql);
        $inSingle = false;
        $inDouble = false;
        $inBacktick = false;
        $inDollar = false; $dollarTag = '';
        $delimiter = ';';
        $i = 0;

        while ($i < $len) {
            // DELIMITER (jen mimo stringy/$$)
            if (!$inSingle && !$inDouble && !$inBacktick && !$inDollar) {
                if (preg_match('~\G\s*DELIMITER\s+(\S+)~Ai', $sql, $m, 0, $i)) {
                    $delimiter = $m[1];
                    $nl = strpos($sql, "\n", $i);
                    $i = $nl === false ? $len : $nl + 1;
                    continue;
                }
            }

            $ch   = $sql[$i];
            $next = ($i + 1 < $len) ? $sql[$i + 1] : '';
            $prev = ($i > 0) ? $sql[$i - 1] : '';

            // PG $tag$...$tag$
            if (!$inSingle && !$inDouble && !$inBacktick) {
                if (!$inDollar && $ch === '$') {
                    if (preg_match('~\G\$([A-Za-z0-9_]*)\$~A', $sql, $m, 0, $i)) {
                        $inDollar = true; $dollarTag = $m[1];
                        $buf .= $m[0]; $i += strlen($m[0]);
                        continue;
                    }
                } elseif ($inDollar) {
                    $endTag = '$'.$dollarTag.'$';
                    if (substr($sql, $i, strlen($endTag)) === $endTag) {
                        $buf .= $endTag; $i += strlen($endTag);
                        $inDollar = false; $dollarTag = '';
                        continue;
                    }
                    $buf .= $ch; $i++; continue;
                }
            }

            // Uvnitř stringů/identifikátorů – respektuj escapování
            if ($inSingle) {
                if ($ch === "'" && $next === "'") { $buf .= "''"; $i += 2; continue; }
                $buf .= $ch; $i++;
                if ($ch === "'" && $prev !== "\\") { $inSingle = false; }
                continue;
            }
            if ($inDouble) {
                if ($ch === '"' && $next === '"') { $buf .= '""'; $i += 2; continue; }
                $buf .= $ch; $i++;
                if ($ch === '"' && $prev !== "\\") { $inDouble = false; }
                continue;
            }
            if ($inBacktick) {
                if ($ch === '`' && $next === '`') { $buf .= '``'; $i += 2; continue; }
                $buf .= $ch; $i++;
                if ($ch === '`') { $inBacktick = false; }
                continue;
            }

            // Otevírání stringů/identifikátorů
            if ($ch === "'") { $inSingle = true;  $buf .= $ch; $i++; continue; }
            if ($ch === '"') { $inDouble = true;  $buf .= $ch; $i++; continue; }
            if ($ch === '`') { $inBacktick = true; $buf .= $ch; $i++; continue; }

            // Konec statementu dle delimiteru
            if ($delimiter === ';') {
                if ($ch === ';') {
                    $trim = trim($buf); if ($trim !== '') $out[] = $trim;
                    $buf = ''; $i++; continue;
                }
            } else {
                if ($delimiter !== '' && substr($sql, $i, strlen($delimiter)) === $delimiter) {
                    $trim = trim($buf); if ($trim !== '') $out[] = $trim;
                    $buf = ''; $i += strlen($delimiter); continue;
                }
            }

            $buf .= $ch; $i++;
        }

        $trim = trim($buf);
        if ($trim !== '') $out[] = $trim;
        return $out;
    }

    private function wantsSeedsInChecksum(): bool
    {
        return getenv('BC_CHECKSUM_INCLUDE_SEEDS') === '1';
    }

    /**
     * Respektuje direktivy v CREATE VIEW přesně tak, jak jsou ve schématu.
     * Nic nepřidává ani nepřepisuje. Volitelně můžeš odstranit DEFINER přes env.
     */
    private function normalizeCreateViewDirectives(string $stmt): string
    {
        if (!$this->dialect->isMysql()) {
            return $stmt;
        }
        // Pokud chceš z provozních důvodů odstranit DEFINER, zapni BC_STRIP_DEFINER=1
        if (getenv('BC_STRIP_DEFINER') === '1') {
            return preg_replace('~\bDEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)~i', '', $stmt);
        }
        return $stmt;
    }

    public function __construct(
        private Database $db,
        private SqlDialect $dialect
    ) {
        $this->ddlGuard = new DdlGuard($db, $dialect, $db->getLogger());
        $this->debug      = (getenv('BC_INSTALLER_DEBUG') === '1');
        $this->traceSql   = (getenv('BC_INSTALLER_TRACE_SQL') === '1');
        $this->traceFiles = (getenv('BC_INSTALLER_TRACE_FILES') === '1');
        $this->verbose    = (getenv('BC_INSTALLER_DEBUG_VERBOSE') === '1');
        if ($this->debug) {
            error_log('[Installer][DEBUG] BC_INSTALLER_DEBUG=1 → SQL tracing (Installer) enabled');
        }
    }

    public function ensureRegistry(): void
    {
        if ($this->registryEnsured) { return; }   // ← short-circuit
        $ddl = $this->dialect->isMysql()
            ? "CREATE TABLE IF NOT EXISTS _schema_registry (
                 module_name  VARCHAR(200) PRIMARY KEY,
                 version      VARCHAR(20)  NOT NULL,
                 installed_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                 checksum     VARCHAR(64)  NOT NULL
               )"
            : "CREATE TABLE IF NOT EXISTS _schema_registry (
                 module_name  VARCHAR(200) PRIMARY KEY,
                 version      VARCHAR(20)  NOT NULL,
                 installed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                 checksum     VARCHAR(64)  NOT NULL
               )";
    if (!$this->traceSql) {
        $this->dbg('ensureRegistry DDL: ' . $this->head($ddl));
    }
        $this->qexec($ddl);                   // <— Core má nově exec()
        $this->registryEnsured = true;            // ← zapamatuj
    }

    private function dbg(string $msg): void {
        if ($this->debug) { error_log('[Installer][DEBUG] ' . $msg); }
    }

    private function diagEnabled(): bool {
        return $this->debug || getenv('BC_INSTALLER_DIAG') === '1';
    }
    private function dlog(string $msg): void {
        if ($this->diagEnabled()) { error_log('[Installer][DIAG] ' . $msg); }
    }

    private function isMariaDb(): bool
    {
        if (!$this->dialect->isMysql()) return false;
        try {
            // MariaDB to má v @@version_comment, fallback na VERSION()
            $vc = (string)($this->db->fetchOne("SELECT @@version_comment") ?? '');
            if ($vc === '') { $vc = (string)($this->db->fetchOne("SELECT VERSION()") ?? ''); }
            return stripos($vc, 'mariadb') !== false;
        } catch (\Throwable) {
            return false;
        }
    }

    private function traceViewAlgorithms(): void
    {
        if (getenv('BC_TRACE_VIEWS') !== '1') return;

        if ($this->dialect->isMysql() && !$this->isMariaDb()) {
            // --- MySQL: parsuj z SHOW CREATE VIEW ---
            $views = $this->db->fetchAll(
                "SELECT TABLE_NAME AS name
                FROM information_schema.VIEWS
                WHERE TABLE_SCHEMA = DATABASE()
            ORDER BY TABLE_NAME"
            ) ?? [];

            foreach ($views as $v) {
                $name = (string)$v['name'];
                try {
                    $row = $this->db->fetch('SHOW CREATE VIEW ' . $this->db->quoteIdent($name)) ?? [];
                    // Klíč se obvykle jmenuje 'Create View'
                    $ddl = (string)($row['Create View'] ?? (array_values($row)[1] ?? ''));
                    $alg = 'UNKNOWN';
                    if (preg_match('~\bALGORITHM\s*=\s*(UNDEFINED|MERGE|TEMPTABLE)\b~i', $ddl, $m)) {
                        $alg = strtoupper($m[1]);
                    }
                    error_log('[Installer][TRACE_VIEWS_ALG] ' . $name . ' → ' . $alg);
                } catch (\Throwable $e) {
                    error_log('[Installer][TRACE_VIEWS_ALG][WARN] SHOW CREATE VIEW ' . $name . ' failed: ' . $e->getMessage());
                }
            }
            return;
        }

        if ($this->isMariaDb()) {
            // --- MariaDB: ALGORITHM je v information_schema.VIEWS ---
            try {
                $rows = $this->db->fetchAll(
                    "SELECT TABLE_NAME, ALGORITHM
                    FROM information_schema.VIEWS
                    WHERE TABLE_SCHEMA = DATABASE()
                ORDER BY TABLE_NAME"
                ) ?? [];
                foreach ($rows as $r) {
                    error_log('[Installer][TRACE_VIEWS_ALG] ' . $r['TABLE_NAME'] . ' → ' . strtoupper((string)$r['ALGORITHM']));
                }
            } catch (\Throwable $e) {
                error_log('[Installer][TRACE_VIEWS_ALG][WARN] I_S.VIEWS read failed: ' . $e->getMessage());
            }
            return;
        }

        // Postgres (žádný algorithm koncept) – jen zaloguj názvy
        if ($this->dialect->isPg()) {
            try {
                $rows = $this->db->fetchAll(
                "SELECT table_schema, table_name
                    FROM information_schema.views
                WHERE table_schema = ANY (current_schemas(true))
                ORDER BY table_schema, table_name"
            ) ?? [];
            foreach ($rows as $r) {
                error_log('[Installer][TRACE_VIEWS_ALG] ' . $r['table_schema'] . '.' . $r['table_name'] . ' → N/A');
            }
            } catch (\Throwable $e) {
                error_log('[Installer][TRACE_VIEWS_ALG][WARN] I_S.views read failed: ' . $e->getMessage());
            }
        }
    }

    // --- Installer-level SQL wrappers (žádná dědičnost, žádný linter drama) ---

    private function qexec(string $sql): void
    {
        if ($this->traceSql) { $this->logSql($sql, null); }
        $this->db->exec($sql);
    }

    private function qexecute(string $sql, array $params = []): void
    {
        if ($this->traceSql) { $this->logSql($sql, $params); }
        $this->db->execute($sql, $params);
    }

    // ---------- interní trace utility (původně v proxy) ----------

    private function logSql(string $sql, ?array $params): void
    {
        $kind   = $this->classify($sql, $objName);
        $head   = $this->firstLine($sql);
        $origin = $this->findOrigin();
        $from   = $origin ? ($origin['file'] . ':' . $origin['line']) : '(unknown)';
        $extra  = $objName ? " target={$objName}" : '';
        error_log("[Installer][DEBUG] SQL {$kind}{$extra} from {$from}: {$head}");
    }

    private function classify(string $sql, ?string &$objName): string
    {
        $objName = null;
        $s = ltrim($sql);
        if (preg_match('~^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(`?"?)([A-Za-z0-9_]+)\1~i', $s, $m)) { $objName = $m[2]; return 'CREATE TABLE'; }
        if (preg_match('~^ALTER\s+TABLE\s+(`?"?)([A-Za-z0-9_]+)\1~i', $s, $m))                    { $objName = $m[2]; return 'ALTER TABLE'; }
        if (preg_match('~^DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?(`?"?)([A-Za-z0-9_]+)\1~i', $s, $m))  { $objName = $m[2]; return 'DROP TABLE'; }
        if (preg_match(
            '~^CREATE\s+(?:OR\s+REPLACE\s+)?'
        . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*'
        . 'VIEW\s+(`?"?)([A-Za-z0-9_]+)\1~i',
            $s, $m
        )) { $objName = $m[2]; return 'CREATE VIEW'; }
        if (preg_match('~^DROP\s+VIEW\s+(?:IF\s+EXISTS\s+)?(`?"?)([A-Za-z0-9_]+)\1~i', $s, $m))   { $objName = $m[2]; return 'DROP VIEW'; }
        if (preg_match('~^CREATE\s+(?:UNIQUE\s+)?INDEX\s+(`?"?)([A-Za-z0-9_]+)\1.*\s+ON\s+(`?"?)([A-Za-z0-9_]+)\3~i', $s, $m)) {
            $objName = $m[2] . ' ON ' . $m[4]; return 'CREATE INDEX';
        }
        if (preg_match('~^BEGIN\b|^COMMIT\b|^ROLLBACK\b~i', $s)) return 'TXN';
        return 'SQL';
    }

    private function firstLine(string $sql): string
    {
        $one = preg_replace("~\r\n?~", "\n", trim($sql));
        $one = strtok($one, "\n");
        $one = preg_replace('~\s+~', ' ', $one);
        return mb_substr($one, 0, 200);
    }

    private function findOrigin(): ?array
    {
        // schovej vlastní rámce Installeru, ať je vidět „skutečné“ volání
        $excludeRe = '~(src[\\/ ]Installer\.php$|[\\/]vendor[\\/])~i';
        foreach (debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS) as $f) {
            if (empty($f['file'])) { continue; }
            if (preg_match($excludeRe, $f['file'])) { continue; }
            return ['file' => $f['file'], 'line' => $f['line'] ?? 0];
        }
        return null;
    }

    // --- DB existence helpers ----------------------------------------------------

    private function mysqlVersionNumber(): string
    {
        $fallback = '8.0.20';
        try {
            if (method_exists($this->db, 'serverVersion')) {
                $v = (string)($this->db->serverVersion() ?? $fallback);
            } else {
                $v = (string)($this->db->fetchOne('SELECT VERSION()') ?? $fallback);
            }
            // ořež vše za první „číslo.tečka…“
            $num = (string)preg_replace('~^([0-9]+(?:\.[0-9]+){1,2}).*$~', '$1', $v);
            return $num !== '' ? $num : $fallback;
        } catch (\Throwable) {
            return $fallback;
        }
    }

    private function extractCreateViewStmtsRaw(string $rawSql): array {
        $out = [];
        $re  = '~CREATE\s+(?:OR\s+REPLACE\s+)?'
            . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*'
            . 'VIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS\b.*?;~is';
        if (preg_match_all($re, $rawSql, $mm, PREG_SET_ORDER)) {
            foreach ($mm as $m) {
                $view = str_replace(['`','"'], '', $m[1]);  // nech klidně schema.view
                $out[] = [$view, trim($m[0])];
            }
        }
        return $out;
    }

    /** Vrátí true, pokud tabulka existuje v aktuálním schématu/databázi. */
    private function tableExists(?string $name): bool
    {
        if ($name === null || $name === '') return false;

        if ($this->dialect->isMysql()) {
            $sql = "SELECT COUNT(*)
                    FROM information_schema.tables
                    WHERE table_schema = DATABASE()
                    AND table_type = 'BASE TABLE'
                    AND LOWER(table_name) = LOWER(:t)";
        } else {
            $sql = "SELECT COUNT(*)
                    FROM information_schema.tables
                    WHERE table_schema = ANY (current_schemas(true))
                    AND table_type = 'BASE TABLE'
                    AND LOWER(table_name) = LOWER(:t)";
        }
        $cnt = (int)$this->db->fetchOne($sql, [':t' => $name]);
        $this->dbg("tableExists({$name}) => {$cnt}");
        return $cnt > 0;
    }

    /** Vrátí true, pokud view existuje v aktuálním schématu/databázi. */
    private function viewExists(string $name): bool
    {
        $schema = null; $base = $name;
        if (str_contains($name, '.')) { [$schema, $base] = explode('.', $name, 2); }

        if ($this->dialect->isMysql()) {
            if ($schema) {
                $sql = "SELECT COUNT(*) FROM information_schema.views
                        WHERE LOWER(table_schema)=LOWER(:s) AND LOWER(table_name)=LOWER(:v)";
                return (bool)$this->db->fetchOne($sql, [':s'=>$schema, ':v'=>$base]);
            }
            $sql = "SELECT COUNT(*) FROM information_schema.views
                    WHERE table_schema = DATABASE() AND LOWER(table_name)=LOWER(:v)";
            return (bool)$this->db->fetchOne($sql, [':v'=>$base]);
        } else {
            if ($schema) {
                $sql = "SELECT COUNT(*) FROM information_schema.views
                        WHERE LOWER(table_schema)=LOWER(:s) AND LOWER(table_name)=LOWER(:v)";
                return (bool)$this->db->fetchOne($sql, [':s'=>$schema, ':v'=>$base]);
            }
            $sql = "SELECT COUNT(*) FROM information_schema.views
                    WHERE table_schema = ANY (current_schemas(true)) AND LOWER(table_name)=LOWER(:v)";
            return (bool)$this->db->fetchOne($sql, [':v'=>$base]);
        }
    }

    /** Detailní seznam chybějících view pro modul (case-insensitive). */
    private function viewsMissingList(ModuleInterface $m): array
    {
        $decl = $this->declaredViewsFor($m);
        if (!$decl) return [];
        $missing = [];
        foreach ($decl as $v) {
            if (!$this->viewExists($v)) { $missing[] = $v; }
        }
        return $missing;
    }

    /**
     * Z 040_views.*.sql pro daný modul vyparsuje názvy view.
     * Používá stejný regexp jako replayViewsScript().
     */
    private function declaredViewsFor(ModuleInterface $m): array
    {
        $dir  = $this->schemaDirBesideSrc($m);
        $dial = $this->dialect->isMysql() ? 'mysql' : 'postgres';
        $files = glob($dir . '/040_views.' . $dial . '.sql') ?: [];

        $names = [];
        foreach ($files as $file) {
            $sql = (string)@file_get_contents($file);
            if ($sql === '') continue;
            if (preg_match_all(
                '~CREATE\s+(?:OR\s+REPLACE\s+)?'
            . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*'
            . 'VIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS~i',
                $sql, $mm
            )) {
                foreach ($mm[1] as $full) {
                    $v = strtolower(str_replace(['`','"'],'', $full));
                    $base = str_contains($v,'.') ? substr($v, strrpos($v,'.')+1) : $v;
                    $names[$base] = $base;
                }
            }
        }
        return array_values($names);
    }

    /** True, pokud modul deklaruje nějaké view a alespoň jedno v DB chybí. */
    private function moduleViewsMissing(ModuleInterface $m): bool
    {
        return $this->viewsMissingList($m) !== [];
    }

    /** Finální seznam schema souborů pro modul (reálné cesty + sha/len). */
    private function debugSchemaFiles(ModuleInterface $m): void {
        if (!$this->traceFiles) return;
        $files = $this->schemaFilesFor($m, $this->dialect);
        $this->dbg("schema[{$m->name()}] dialect={$this->dialect->value} files=" . count($files));
        foreach ($files as $f) {
            $raw = (string)@file_get_contents($f);
            $canon = $this->canonicalizeSql($raw, $this->dialect);
            $sha = hash('sha256', $canon);
            $len = strlen($canon);
            $this->dbg("  - " . basename($f) . " → " . realpath($f) . " sha256={$sha} len={$len}");
        }
    }

    /** Na jeden řádek stáhne SQL (pro lokální logy v Installer metodách). */
    private function head(string $sql): string {
        $s = preg_replace("~\r\n?~", "\n", $sql);
        foreach (explode("\n", $s) as $line) {
            $t = trim($line);
            if ($t === '' || str_starts_with($t, '--') || str_starts_with($t, '#') || str_starts_with($t, '/*')) continue;
            return preg_replace('~\s+~', ' ', $t);
        }
        return '';
    }

    private function isInstalled(string $name): bool {
        return $this->getVersion($name) !== null;
    }

    private function assertDependenciesInstalled(ModuleInterface $m): void {
        $missing = [];
        foreach ($m->dependencies() as $dep) {
            if (!$this->isInstalled($dep)) { $missing[] = $dep; }
        }
        if ($missing) {
            $list = implode(', ', $missing);
            throw new \RuntimeException(
                "Cannot install '{$m->name()}' – missing dependencies: {$list}. ".
                "Run installOrUpgradeAll([...]) with all modules in one go."
            );
        }
    }

    public function installOrUpgrade(ModuleInterface $m): void
    {
        $seq = ++$this->runSeq;
        $this->dbg("module={$m->name()} target={$m->version()}");
        $this->dlog("BEGIN #{$seq} module={$m->name()} target={$m->version()} dialect={$this->dialect->value}");
        $schemaDir = $this->schemaDirBesideSrc($m);
        $this->dlog("schemaDir -> " . ($schemaDir ?: '(empty)'));
        $filesForDial = $this->schemaFilesFor($m, $this->dialect);
        $this->dlog("filesForDial[".count($filesForDial)."] -> " . implode(', ', array_map('basename', $filesForDial)));
        $decl = $this->declaredViewsFor($m);
        $this->dlog("declaredViews[".count($decl)."] -> " . implode(', ', $decl));
        $missingBefore = $this->viewsMissingList($m);
        $this->dlog("viewsMissing BEFORE replay[".count($missingBefore)."] -> " . implode(', ', $missingBefore));
        $this->debugSchemaFiles($m);
        $this->ensureRegistry();

        $supported = $m->dialects();
        if ($supported && !in_array($this->dialect->value, $supported, true)) {
            throw new \RuntimeException("Module {$m->name()} does not support dialect {$this->dialect->value}");
        }

        $reg      = $this->db->fetch("SELECT version,checksum FROM _schema_registry WHERE module_name=:n", [':n'=>$m->name()]) ?? [];
        $current  = $reg['version']  ?? null;
        $prevChk  = $reg['checksum'] ?? null;
        $newChk   = $this->computeChecksum($m);
        if ($this->verbose || $current === null || version_compare($current, $m->version(), '<')) {
            $this->dbg("installed={$current} checksum.prev=" . ($prevChk ?? 'null') . " checksum.new={$newChk}");
        }
        $forceRepair  = (getenv('BC_REPAIR') === '1');
        $didWork      = false;

        // --- rozhodnutí o instalaci/upgrade s kontrolou existence primární tabulky ---
        $primaryTable = $m->table();
        $hasPrimaryTable = $primaryTable ? $this->tableExists($primaryTable) : true;

        if ($current === null || !$hasPrimaryTable) {
            $this->assertDependenciesInstalled($m);
            if ($current === null) {
                $this->dbg("install() begin for {$m->name()} (reason=" . ($current===null?'no-registry':'') . ")");
            } else {
                $this->dbg("install() begin for {$m->name()} (reason=missing-primary-table '{$primaryTable}')");
            }
            $m->install($this->db, $this->dialect);
            $this->dbg("install() done for {$m->name()}");
            $didWork = true;
        }
        elseif (version_compare($current, $m->version(), '<')) {
            $this->assertDependenciesInstalled($m);
            $this->dbg("upgrade() {$current} → {$m->version()} begin for {$m->name()}");
            $m->upgrade($this->db, $this->dialect, $current);
            $this->dbg("upgrade() done for {$m->name()}");
            $didWork = true;
        }

        // --- checksum drift (jen informace pro rozhodnutí níž) ---
        $checksumDrift = ($prevChk !== null && $prevChk !== $newChk);

        // --- post-check indexů (zůstává) ---
        if ($didWork || $forceRepair) {
            $st = $m->status($this->db, $this->dialect);
            if (!empty($st['missing_idx'])) {
                $this->replayIndexScript($m);
                $st2 = $m->status($this->db, $this->dialect);
                if (!empty($st2['missing_idx'])) {
                    throw new \RuntimeException(
                        $m->name() . " still missing indexes: " . implode(',', $st2['missing_idx'])
                    );
                }
            }
        }

        // --- robustní rozhodnutí, zda přehrát VIEW skript ---
        $viewsMissing = $this->moduleViewsMissing($m);
        $needsViews = $didWork || $forceRepair || $checksumDrift || $viewsMissing;

        if ($needsViews) {
            $reason = [];
            if ($didWork)       $reason[] = 'didWork';
            if ($forceRepair)   $reason[] = 'force';
            if ($checksumDrift) $reason[] = 'drift';
            if ($viewsMissing)  $reason[] = 'views-missing';
            $this->dbg('views: replay (' . implode(', ', $reason) . ')');
            $this->replayViewsScript($m);
            $missingAfter = $this->viewsMissingList($m);
            $this->dlog("viewsMissing AFTER replay[".count($missingAfter)."] -> " . implode(', ', $missingAfter));
            if ($missingAfter) { $this->dumpViewDefinitions($missingAfter); }
        } else {
            if (empty($this->viewsSkipNotified[$m->name()])) {
                $this->viewsSkipNotified[$m->name()] = true;
                $this->dbg("views: skip (no work, no force, no drift, all-present)");
            }
        }

        // --- verzi zapisujeme až po green post-checku ---
        $this->upsertVersion($m, $newChk);
        $this->traceViewAlgorithmsFiltered($decl);

        $this->dlog("END   #{$seq} module={$m->name()}");
    }

    /** @param ModuleInterface[] $modules */
    public function installOrUpgradeAll(array $modules): void
    {
        $this->ensureRegistry();
        foreach ($this->toposort($modules) as $m) {
            $this->installOrUpgrade($m);
        }
    }

    /** @param ModuleInterface[] $modules */
    public function status(array $modules): array
    {
        $out = [];
        foreach ($modules as $m) {
            $name = $m->name();
            $installed = $this->getVersion($name);
            $target    = $m->version();

            $needsInstall = ($installed === null);
            $needsUpgrade = ($installed !== null && version_compare($installed, $target, '<'));

            $modStatus = [];
            try { $modStatus = $m->status($this->db, $this->dialect); } catch (\Throwable) {}

            $out[$name] = [
                'module'        => $name,
                'table'         => $m->table(),
                'installed'     => $installed,
                'target'        => $target,
                'needsInstall'  => $needsInstall,
                'needsUpgrade'  => $needsUpgrade,
                'dialects'      => $m->dialects(),
                'dependencies'  => $m->dependencies(),
                'checksum'      => $this->computeChecksum($m),
                'moduleStatus'  => $modStatus,
            ];
        }
        return $out;
    }

    // ---------- interní pomocníci ----------

    private function getVersion(string $name): ?string
    {
        $sql = "SELECT version FROM _schema_registry WHERE module_name = :name";
        $val = $this->db->fetchOne($sql, [':name' => $name]);     // <— alias v Core
        return $val !== null ? (string)$val : null;
    }

    private function upsertVersion(ModuleInterface $m, string $checksum): void
    {
        if ($this->dialect->isMysql()) {
            $params = [
                ':name'     => $m->name(),
                ':version'  => $m->version(),
                ':checksum' => $checksum,
            ];

            // 1) univerzálně kompatibilní forma (funguje v MariaDB i MySQL < 8.0.20)
            $sqlValues = "INSERT INTO _schema_registry(module_name,version,checksum)
                        VALUES(:name,:version,:checksum)
                        ON DUPLICATE KEY UPDATE version=VALUES(version), checksum=VALUES(checksum)";

            // 2) forma pro MySQL ≥ 8.0.20 (VALUES() odstraněno – nutný alias)
            $sqlAlias  = "INSERT INTO _schema_registry AS new (module_name,version,checksum)
                        VALUES(:name,:version,:checksum)
                        ON DUPLICATE KEY UPDATE version=new.version, checksum=new.checksum";

            try {
                // Zkus nejdřív VALUES() – pokryje MariaDB i starší MySQL.
                $this->qexecute($sqlValues, $params);
            } catch (\Throwable $e) {
                // MySQL 8.0.20+ hlásí 1305: "FUNCTION ... VALUES does not exist"
                $code = $e instanceof \PDOException ? ($e->errorInfo[1] ?? null) : null;
                if ($code === 1305) {
                    // Přepni na aliasovou syntaxi
                    $this->qexecute($sqlAlias, $params);
                } else {
                    throw $e;
                }
            }
            return;
        }

        // PostgreSQL
        $sql = "INSERT INTO _schema_registry(module_name,version,checksum)
                VALUES(:name,:version,:checksum)
                ON CONFLICT (module_name)
                DO UPDATE SET version=EXCLUDED.version, checksum=EXCLUDED.checksum";
        $this->qexecute($sql, [
            ':name'     => $m->name(),
            ':version'  => $m->version(),
            ':checksum' => $checksum,
        ]);
    }
    
    /**
     * Přehraje pouze indexový skript 020_indexes.<dial>.sql pro daný modul.
     * Používá reflection k nalezení ../schema vedle *Module.php.
     */
    private function replayIndexScript(ModuleInterface $m): void
    {
        $dir  = $this->schemaDirBesideSrc($m);
        $dial = $this->dialect->isMysql() ? 'mysql' : 'postgres';
        $this->dbg("indexes: scanning in {$dir} (dialect={$dial})");

        // Podporuj obě pojmenování: 020_indexes.postgres.sql i 020_indexes_postgres.sql
        $candidates = glob($dir . '/020_indexes.' . $dial . '.sql') ?: [];

        foreach ($candidates as $path) {
            $this->dbg("indexes: file " . basename($path) . " → " . realpath($path));
            $sql = @file_get_contents($path);
            if ($sql === false) { continue; }

            // Bezpečné rozsekání: odstranit komentáře a pak tokenize
            $sql   = (string)$sql;
            $sql   = $this->stripSqlComments($sql);
            $stmts = $this->splitSqlStatements($sql);
            foreach ($stmts as $stmt) {
                $stmt = trim($stmt);
                if ($stmt !== '') {
                    if (!preg_match('~^(CREATE\s+INDEX|CREATE\s+UNIQUE\s+INDEX|ALTER\s+TABLE|DROP\s+INDEX)~i', $stmt)) {
                        continue;
                    }
                    if (!$this->traceSql && $this->diagEnabled()) {
                        $this->dbg("indexes: exec " . $this->head($stmt));
                    }
                    $this->qexec($stmt);   // ← zajistí klasifikaci + log SQL
                }
            }
        }
    }
    
    private function replayViewsScript(ModuleInterface $m): void
    {
        $dir  = $this->schemaDirBesideSrc($m);
        $dial = $this->dialect->isMysql() ? 'mysql' : 'postgres';
        // Pouze view, které patří aktuálnímu modulu
        $targetView = strtolower((string)$m::contractView());
        $filterByContract = $targetView !== '';

        if ($this->traceFiles) { $this->dbg("views: scanning in {$dir} (dialect={$dial})"); }

        $cands = glob($dir . '/040_views.' . $dial . '.sql') ?: [];
        if (!$cands) { $this->dlog("views: no candidates in {$dir} for dial={$dial}"); return; }
        foreach ($cands as $file) {
            if ($this->traceFiles) { $this->dbg("views: file " . basename($file) . " → " . realpath($file)); }

            // čti RAW text; ltrim jen BOM, ale nestripuj komentáře (ještě ne)
            $raw = (string)@file_get_contents($file);
            if ($raw === '') { continue; }
            $raw = ltrim($raw, "\xEF\xBB\xBF");

            // Primární cesta: strip → split → filtr
            // dovol "…; CREATE …" na jednom řádku
            $sqlNoComments = $this->stripSqlComments($raw);

            $stmts     = $this->splitSqlStatements($sqlNoComments);
            $execCount = 0; $ignored = 0;

            foreach ($stmts as $stmt) {
                $stmt = trim($stmt);
                if ($stmt === '') { continue; }

                // Zajímá nás jen DROP VIEW a CREATE VIEW; na DROP použijeme best-effort, CREATE přenecháme DdlGuardu
                if (preg_match('~^DROP\s+VIEW\b~i', $stmt)) {
                    // DROPy ignorujeme – o drop se postará DdlGuard (dropFirst=true).
                    $ignored++;
                    continue;
                }
                // Pokud filtrujeme na contract view, přeskakuj cizí view
                if ($filterByContract) {
                    if (preg_match('~\bVIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS\b~i', $stmt, $mm)) {
                        $vraw  = $mm[1];
                        $vname = strtolower(str_replace(['`','"'],'',$vraw));
                        $vbase = str_contains($vname,'.') ? substr($vname, strrpos($vname,'.')+1) : $vname;
                        if ($vbase !== $targetView) { $ignored++; continue; }
                    } else {
                        $ignored++; 
                        continue;
                    }
                }

                if (preg_match(
                    '~^CREATE\s+(?:OR\s+REPLACE\s+)?'
                . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*VIEW\b~i',
                    $stmt
                )) {
                    if (!$this->traceSql && $this->diagEnabled()) { $this->dbg("views: guarded " . $this->head($stmt)); }
                    $stmt = $this->normalizeCreateViewDirectives($stmt);
                    // deleguj robustní CREATE VIEW na DdlGuard
                    $this->ddlGuard->applyCreateView($stmt, [
                        'lockTimeoutSec'    => (int)(getenv('BC_VIEW_LOCK_TIMEOUT') ?: 10),
                        'retries'           => (int)(getenv('BC_INSTALLER_VIEW_RETRIES') ?: 3),
                        'fenceMs'           => (int)(getenv('BC_VIEW_FENCE_MS') ?: 600),
                        'dropFirst'         => true,
                        'normalizeOrReplace'=> true,
                    ]);
                    $execCount++;
                    continue;
                }

                // všechno ostatní ignoruj v rámci 040_views.*.sql
                $ignored++;
            }

            if ($execCount === 0) {
                $fb = $this->extractCreateViewStmtsRaw($raw);
                if ($fb) {
                    $this->dbg("views: fallback-extractor executing " . count($fb) . " CREATE VIEW stmt(s)");
                    foreach ($fb as [$vname, $stmt]) {
                        $vbase = strtolower(preg_replace('~^.*\.~','', str_replace(['`','"'],'',$vname)));
                        if ($filterByContract && $vbase !== $targetView) { $ignored++; continue; }
                        $stmt = $this->normalizeCreateViewDirectives($stmt);
                        if (!$this->traceSql && $this->diagEnabled()) { $this->dbg("views: guarded-fallback " . $this->head($stmt)); }
                        $this->ddlGuard->applyCreateView($stmt, [
                            'lockTimeoutSec'     => (int)(getenv('BC_VIEW_LOCK_TIMEOUT') ?: 10),
                            'retries'            => (int)(getenv('BC_INSTALLER_VIEW_RETRIES') ?: 3),
                            'fenceMs'            => (int)(getenv('BC_VIEW_FENCE_MS') ?: 600),
                            'dropFirst'          => true,
                            'normalizeOrReplace' => true,
                        ]);
                        $execCount++;
                    }
                } else {
                    $this->dbg("views: fallback-extractor found 0 CREATE VIEW stmt(s)");
                }
            }

            // Post-kontrola: co mělo vzniknout vs. co existuje
            $declared = [];
            if (preg_match_all('~VIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS~i', $raw, $mmm)) {
                $declared = array_values(array_unique(array_map(function($x){
                    $x = strtolower(str_replace(['`','"'],'',$x));
                    return str_contains($x,'.') ? substr($x, strrpos($x,'.')+1) : $x;
                }, $mmm[1])));
                if ($filterByContract) {
                    $declared = array_values(array_filter($declared, fn($v) => $v === $targetView));
                }
            }
            $missing = array_values(array_filter($declared, fn($v) => !$this->viewExists($v)));

            $this->dbg("views: stmt_total=" . count($stmts) . " exec=" . $execCount . " ignored=" . $ignored
                    . " missing_after=[" . implode(', ', $missing) . "]");

            if ($missing && getenv('BC_INSTALLER_STRICT_VIEWS') === '1') {
                throw new \RuntimeException('Views not created: ' . implode(', ', $missing));
            }
        }
    }

    /** Vytiskne SHOW CREATE VIEW/pg_get_viewdef pro diagnostiku chybějících view. */
    private function dumpViewDefinitions(array $names): void
    {
        $qi = function(string $fqn): string {
            $parts = explode('.', $fqn);
            return implode('.', array_map(fn($p) => $this->db->quoteIdent($p), $parts));
        };
        foreach ($names as $name) {
            try {
                if ($this->dialect->isMysql()) {
                    $row = $this->db->fetch('SHOW CREATE VIEW ' . $qi($name)) ?? [];
                    $ddl = (string)($row['Create View'] ?? (array_values($row)[1] ?? ''));
                    $hash = $ddl !== '' ? substr(hash('sha256', $ddl), 0, 12) : 'null';
                    $this->dlog("SHOW CREATE VIEW " . $name . " -> hash=" . $hash . " head=" . substr(preg_replace('~\\s+~',' ', $ddl), 0, 160));
                } else {
                    $row = $this->db->fetch("SELECT n.nspname AS s, c.relname AS n, pg_get_viewdef(c.oid, true) AS def
                                              FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                                              WHERE c.relkind='v' AND lower(c.relname)=lower(:v) AND n.nspname = ANY (current_schemas(true))",
                                              [':v'=>$name]) ?? [];
                    $ddl = (string)($row['def'] ?? '');
                    $hash = $ddl !== '' ? substr(hash('sha256', $ddl), 0, 12) : 'null';
                    $this->dlog("pg_get_viewdef " . $name . " -> hash=" . $hash . " head=" . substr(preg_replace('~\\s+~',' ', $ddl), 0, 160));
                }
            } catch (\Throwable $e) {
                $this->dlog("viewDef ERR " . $name . " -> " . $e->getMessage());
            }
        }
    }

    /** Filtrovaný výpis algoritmů jen pro view, která daný modul opravdu deklaruje. */
    private function traceViewAlgorithmsFiltered(array $onlyThese): void
    {
        if (getenv('BC_TRACE_VIEWS') !== '1') return;
        if (!$onlyThese) { $this->traceViewAlgorithms(); return; } // fallback na původní
        try {
            $qi = function(string $fqn): string {
                $parts = explode('.', $fqn);
                return implode('.', array_map(fn($p) => $this->db->quoteIdent($p), $parts));
            };
            if ($this->dialect->isMysql() && !$this->isMariaDb()) {
                foreach ($onlyThese as $name) {
                    try {
                        $row = $this->db->fetch('SHOW CREATE VIEW ' . $qi($name)) ?? [];
                        $ddl = (string)($row['Create View'] ?? (array_values($row)[1] ?? ''));
                        $alg = 'UNKNOWN';
                        if (preg_match('~\\bALGORITHM\\s*=\\s*(UNDEFINED|MERGE|TEMPTABLE)\\b~i', $ddl, $m)) {
                            $alg = strtoupper($m[1]);
                        }
                        error_log('[Installer][TRACE_VIEWS_ALG] ' . $name . ' -> ' . $alg);
                    } catch (\Throwable $e) {
                        error_log('[Installer][TRACE_VIEWS_ALG][WARN] SHOW CREATE VIEW ' . $name . ' failed: ' . $e->getMessage());
                    }
                }
                return;
            }
        } catch (\Throwable $e) {
            error_log('[Installer][TRACE_VIEWS_ALG][WARN] filtered failed: ' . $e->getMessage());
        }
        // na ostatní případy nech původní chování
        $this->traceViewAlgorithms();
    }

    public function replayViews(bool $force = false): void
    {
        // Views se už přehrávají per-modul uvnitř installOrUpgrade() -> replayViewsScript($m).
        // Tuhle no-op metodu necháváme jen kvůli kompatibilitě s DbHarness (method_exists).
    }

    private function computeChecksum(ModuleInterface $m): string
    {
        $files = $this->schemaFilesFor($m, $this->dialect);
        $list  = [];

        foreach ($files as $f) {
            if (!$this->wantsSeedsInChecksum()) {
                $bn = basename($f);
                if (preg_match('~^050_seeds(?:\.|_)(mysql|postgres)\.sql$~i', $bn)) {
                    continue;
                }
            }
            $raw   = (string)@file_get_contents($f);
            $canon = $this->canonicalizeSql($raw, $this->dialect);
            $list[] = [
                'name' => basename($f),
                'sha'  => hash('sha256', $canon),
                'len'  => strlen($canon),
            ];
        }

        // Deterministická serializace
        usort($list, fn($a,$b) => strcmp($a['name'], $b['name']));

        $payload = [
            'info'    => $m->info(),
            'dialect' => $this->dialect->value,
            'files'   => $list,
        ];

        return hash('sha256', json_encode($payload, JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE));
    }

    /** Vytáhne schema soubory jen pro aktuální dialekt (podporuje . i _). */
    private function schemaFilesFor(ModuleInterface $m, SqlDialect $dialect): array
    {
        $dir = $this->schemaDirBesideSrc($m);
        $d   = $dialect->isMysql() ? 'mysql' : 'postgres';

        // vezmi všechno *.mysql.sql / *.postgres.sql
        $all = glob($dir . '/*.' . $d . '.sql') ?: [];

        // nech jen striktně NNN_name.<dial>.sql (žádné podtržítkové varianty, žádné volné názvy)
        $all = array_values(array_filter($all, function (string $path) use ($d): bool {
            $bn = basename($path);
            return (bool)preg_match('~^(\\d{3})_[a-z0-9_]+\\.' . preg_quote($d, '~') . '\\.sql$~i', $bn);
        }));

        // deterministické řazení: nejdřív podle NNN, pak podle jména
        usort($all, function (string $a, string $b): int {
            $ba = basename($a); $bb = basename($b);
            preg_match('~^(\\d{3})_~', $ba, $ma);
            preg_match('~^(\\d{3})_~', $bb, $mb);
            $na = isset($ma[1]) ? (int)$ma[1] : 0;
            $nb = isset($mb[1]) ? (int)$mb[1] : 0;
            return ($na !== $nb) ? ($na <=> $nb) : strcasecmp($ba, $bb);
        });

        // realpath kvůli logům; pokud selže, vrať původní cestu
        return array_map(fn($p) => realpath($p) ?: $p, $all);
    }

    /** Kanonizace SQL: norm. EOL, bez komentářů, bez MySQL „noise“ a env řádků. */
    private function canonicalizeSql(string $sql, SqlDialect $dialect): string
    {
        // 0) strip UTF-8 BOM
        if (strncmp($sql, "\xEF\xBB\xBF", 3) === 0) {
            $sql = substr($sql, 3);
        }

        // 1) jednotné EOL + ořez koncových mezer
        $sql = preg_replace("~\r\n?~", "\n", $sql);
        $sql = preg_replace('~[ \t]+$~m', '', $sql);

        // 2) pryč komentáře (best-effort; neparsuje string literály)
        $sql = $this->stripSqlComments($sql);

        // 3) normalizační úpravy podle dialektu
        if ($dialect->isMysql()) {
            // POZOR: ALGORITHM=… a SQL SECURITY … NEODSTRAŇUJEME kvůli checksumu
            // Zahodíme jen prostředí/závislé šumy:
            $sql = preg_replace('~\bDEFINER\s*=\s*[^ ]+~i', '', $sql);
            $sql = preg_replace('~^\s*DELIMITER\s+\S+.*$~mi', '', $sql);
        } else {
            // PG tooling často vkládá SET search_path – je to env-šum
            $sql = preg_replace('~^\s*SET\s+search_path\s+.*$~mi', '', $sql);
        }

        // 4) sjednoť "CREATE OR REPLACE" → "CREATE" (determinističtější hash)
        $sql = preg_replace('~\bCREATE\s+OR\s+REPLACE\b~i', 'CREATE', $sql);

        // 5) ořez vícenásobných prázdných řádků a okolních whitespace
        $sql = preg_replace("~\n{3,}~", "\n\n", $sql);
        $sql = trim($sql) . "\n";

        return $sql;
    }

    /** @return ModuleInterface[] */
    private function toposort(array $modules): array
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
        return $out;
    }
}
