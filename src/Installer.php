<?php
/*
 *       ####                                
 *      ######                              ██╗    ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗     
 *     #########                            ██║    ██║██╔════╝██║     ██╔════╝██╔═══██╗████╗ ████║██╔════╝ 
 *    ##########         ##                 ██║ █╗ ██║█████╗  ██║     ██║     ██║   ██║██╔████╔██║█████╗   
 *    ###########      ####                 ██║███╗██║██╔══╝  ██║     ██║     ██║   ██║██║╚██╔╝██║██╔══╝   
 * ###############   ######                 ╚███╔███╔╝███████╗███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║███████╗
 * ###########  ##  #######                  ╚══╝╚══╝ ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝ 
 * #########    ### #######                  
 * #########     ###  ####                   ██╗  ██╗███████╗██████╗  ██████╗ ██╗ ██████╗███████╗ 
 * ###########    ##    ##                   ██║  ██║██╔════╝██╔══██╗██╔═══██╗██║██╔════╝██╔════╝ 
 * ##########                #               ███████║█████╗  ██████╔╝██║   ██║██║██║     ███████╗ 
 * #######                     ##            ██╔══██║██╔══╝  ██╔══██╗██║   ██║██║██║     ╚════██║ 
 * ##                            ##          ██║  ██║███████╗██║  ██║╚██████╔╝██║╚██████╗███████║ 
 * ######              #######    ##         ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═════╝╚══════╝ 
 * #####            #######  ##   ##       ┌────────────────────────────────────────────────────────────────────────────┐  
 * #####               ####  ##    #         BLACK CAT DATABASE • Arcane Custody Notice                                 │
 * ########             #######    ##        © 2025 Black Cat Academy s. r. o. • All paws reserved.                     │
 * ####                        #     ##      Licensed strictly under the BlackCat Database Proprietary License v1.0.    │
 * ##########                          ##    Evaluation only; commercial rites demand written consent.                  │
 * ####           ######  #        ######    Unauthorized forks or tampering awaken enforcement claws.                  │
 * #####               ##  ##          ##    Reverse engineering, sublicensing, or origin stripping is forbidden.       │
 * ##########   ###  #### ####        #      Liability for lost data, profits, or familiars remains with the summoner.  │
 * ##                 ##  ##       ####      Infringements trigger termination; contact blackcatacademy@protonmail.com. │
 * ###########      ##   # #   ######        Leave this sigil intact—smudging whiskers invites spectral audits.         │
 * #########       #   ##          ##        Governed under the laws of the Slovak Republic.                            │
 * ##############                ###         Motto: “Purr, Persist, Prevail.”                                           │
 * #############    ###############       └─────────────────────────────────────────────────────────────────────────────┘
 */

declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Database\Support\DdlGuard;
use BlackCat\Database\Support\PgCompat;
use BlackCat\Database\Support\SqlSplitter;
use BlackCat\Database\Support\SqlIdentifier as Ident;
use BlackCat\Database\Support\Retry;
use BlackCat\Database\Support\Observability;
use BlackCat\Database\Support\Telemetry;

final class Installer
{
    private DdlGuard $ddlGuard;
    private bool $registryEnsured = false;
    /** Modules already notified with "views: skip" within the current instance */
    private array $viewsSkipNotified = [];
    /** Sequential run ID for readable logs */
    private int $runSeq = 0;
    private bool $debug; // internal flag added for diagnostics
    // finer control of verbosity
    private bool $traceSql = false;
    private bool $traceFiles = false;
    private bool $verbose = false;
    private ?float $sqlTelemetrySample = null;
    // TODO(crypto-integrations): Thread manifest-derived encryption metadata into installer
    // passes so schema diffs can assert DatabaseIngressAdapter coverage (e.g., tables marked
    // encrypted must reference contexts exported by blackcat-crypto-manifests).

    /** One-time guard for PgCompat.install() */
    private bool $pgCompatEnsured = false;
    /** Cache for mysql version number (saves round-trips) */
    private ?string $mysqlVerCache = null;

    private function pdoErrorCode(\Throwable $e): ?int
    {
        $pdo = $e instanceof \PDOException
            ? $e
            : (($e->getPrevious() instanceof \PDOException) ? $e->getPrevious() : null);
        if (!$pdo) return null;
        $ei = is_array($pdo->errorInfo ?? null) ? ($pdo->errorInfo[1] ?? null) : null;
        return $ei !== null ? (int)$ei : (is_numeric($pdo->getCode()) ? (int)$pdo->getCode() : null);
    }

    /** Remove SQL comments while keeping everything else (ALGORITHM, SECURITY, …) */
    private function stripSqlComments(string $sql): string
    {
        if (strncmp($sql, "\xEF\xBB\xBF", 3) === 0) { $sql = substr($sql, 3); }
        $sql = str_replace("\xC2\xA0", ' ', $sql); // NBSP -> space

        $out = '';
        $len = strlen($sql);
        $inSingle = $inDouble = $inBacktick = false;
        $inDollar = false; $dollarTag = '';

        $isMysql = $this->dialect->isMysql();
        $isPg    = $this->dialect->isPg();

        for ($i = 0; $i < $len; ) {
            $ch   = $sql[$i];
            $next = ($i + 1 < $len) ? $sql[$i + 1] : '';

            // --- Dollar-quoted strings (PG)
            if (!$inSingle && !$inDouble && !$inBacktick) {
                if (!$inDollar && $ch === '$') {
                    if (preg_match('~\G\$([A-Za-z0-9_]*)\$~A', $sql, $m, 0, $i)) {
                        $inDollar = true; $dollarTag = $m[1];
                        $out .= $m[0]; $i += strlen($m[0]); continue;
                    }
                } elseif ($inDollar) {
                    $endTag = '$' . $dollarTag . '$';
                    if (substr($sql, $i, strlen($endTag)) === $endTag) {
                        $out .= $endTag; $i += strlen($endTag); $inDollar = false; $dollarTag = ''; continue;
                    }
                    $out .= $ch; $i++; continue;
                }
            }

            // --- Inside quoted strings/idents
            if ($inSingle) { // SQL standard escaping '' inside ''
                if ($ch === "'" && $next === "'") { $out .= "''"; $i += 2; continue; }
                $out .= $ch; $i++;
                if ($ch === "'") { $inSingle = false; }
                continue;
            }
            if ($inDouble) { // identifiers "" with ""-escape
                if ($ch === '"' && $next === '"') { $out .= '""'; $i += 2; continue; }
                $out .= $ch; $i++;
                if ($ch === '"') { $inDouble = false; }
                continue;
            }
            if ($inBacktick) { // MySQL identifiers ``
                if ($ch === '`' && $next === '`') { $out .= '``'; $i += 2; continue; }
                $out .= $ch; $i++;
                if ($ch === '`') { $inBacktick = false; }
                continue;
            }

            // --- Open quotes
            if ($ch === "'") { $inSingle = true;  $out .= $ch; $i++; continue; }
            if ($ch === '"') { $inDouble = true;  $out .= $ch; $i++; continue; }
            if ($ch === '`') { $inBacktick = true; $out .= $ch; $i++; continue; }

            // --- Comments (only when not inside any quote/dollar)
            // /* ... */
            if ($ch === '/' && $next === '*') {
                $end = strpos($sql, '*/', $i + 2);
                if ($end === false) break; // drop rest if unclosed
                $i = $end + 2; // skip comment
                continue;
            }
            // -- ... (MySQL/PG rules)
            if ($ch === '-' && $next === '-') {
                $pre = $i > 0 ? $sql[$i - 1] : "\n";
                $after = ($i + 2 < $len) ? $sql[$i + 2] : ' ';
                $startToken = ctype_space($pre);

                $mysqlOk = $isMysql && $startToken && (ctype_space($after) || ord($after) < 32);
                $pgOk    = $isPg && $startToken;

                if ($mysqlOk || $pgOk) {
                    // skip to EOL
                    while ($i < $len && $sql[$i] !== "\n" && $sql[$i] !== "\r") { $i++; }
                    continue;
                }
            }
            // # ... (MySQL only)
            if ($isMysql && $ch === '#') {
                $pre = $i > 0 ? $sql[$i - 1] : "\n";
                if (ctype_space($pre)) {
                    while ($i < $len && $sql[$i] !== "\n" && $sql[$i] !== "\r") { $i++; }
                    continue;
                }
            }

            $out .= $ch; $i++;
        }

        return $out;
    }

    /** Return path to <repo-root>/schema, ... */
    private function schemaDirBesideSrc(ModuleInterface $m): string
    {
        // 1) explicit override via env (useful in CI/Docker)
        $env = getenv('BC_SCHEMA_DIR');
        if ($env && is_dir($env)) {
            $r = realpath($env);
            return $r ?: $env;
        }

        // 2) find the path to the module class file
        $file = (new \ReflectionClass($m))->getFileName() ?: '';
        $dir  = $file !== '' ? dirname($file) : getcwd();

        // 3) walk upwards...
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

        // 4) fallback
        $fallback = dirname($file) . DIRECTORY_SEPARATOR . '..' . DIRECTORY_SEPARATOR . 'schema';
        $resolvedFallback = realpath($fallback);
        return ($resolvedFallback && is_dir($resolvedFallback)) ? $resolvedFallback : $fallback;
    }

    private function wantsSeedsInChecksum(): bool
    {
        return getenv('BC_CHECKSUM_INCLUDE_SEEDS') === '1';
    }

    /**
     * Respektuje direktivy v CREATE VIEW...
     */
    private function normalizeCreateViewDirectives(string $stmt): string
    {
        if (!$this->dialect->isMysql()) {
            return $stmt;
        }
        // To remove DEFINER, set BC_STRIP_DEFINER=1
        if (getenv('BC_STRIP_DEFINER') === '1') {
            $stmt = (string)(preg_replace('~\bDEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)~i', '', $stmt) ?? $stmt);
            $stmt = (string)(preg_replace('~\s{2,}~', ' ', $stmt) ?? $stmt);
        }
        // Optionally strip ALGORITHM and SQL SECURITY (cleaner diffs between environments)
        if (getenv('BC_STRIP_ALGORITHM') === '1') {
            $stmt = (string)(preg_replace('~\bALGORITHM\s*=\s*\w+\s*~i', '', $stmt) ?? $stmt);
        }
        if (getenv('BC_STRIP_SQL_SECURITY') === '1') {
            $stmt = (string)(preg_replace('~\bSQL\s+SECURITY\s+\w+\s*~i', '', $stmt) ?? $stmt);
        }
        return (string)$stmt;
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
        $this->qexec($ddl);
        // After creating the registry, ensure MariaDB UUID helpers once
        $this->ensureMariaUuidCompat();
        $this->registryEnsured = true;
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
            $vc = (string)($this->qfetchOne("SELECT @@version_comment") ?? '');
            if ($vc === '') { $vc = (string)($this->qfetchOne("SELECT VERSION()") ?? ''); }
            return stripos($vc, 'mariadb') !== false;
        } catch (\Throwable) {
            return false;
        }
    }

    private function ensureMariaUuidCompat(): void
    {
        // only for MariaDB (MySQL has native support)
        if (!$this->dialect->isMysql() || !$this->isMariaDb()) return;

        $ok = false;
        try {
            $rows = $this->qfetchAll("
                SELECT SPECIFIC_NAME AS name, COUNT(*) AS argc
                FROM information_schema.PARAMETERS
                WHERE SPECIFIC_SCHEMA = DATABASE()
                AND SPECIFIC_NAME IN ('BIN_TO_UUID','UUID_TO_BIN')
                GROUP BY SPECIFIC_NAME
            ");
            $argc = [];
            foreach ($rows as $r) { $argc[strtoupper((string)$r['name'])] = (int)$r['argc']; }
            $ok = (isset($argc['BIN_TO_UUID']) && $argc['BIN_TO_UUID'] === 2)
               && (isset($argc['UUID_TO_BIN']) && $argc['UUID_TO_BIN'] === 2);
        } catch (\Throwable) {
            $ok = false;
        }

        if ($ok) {
            if ($this->diagEnabled()) { $this->dbg('maria-compat: UUID funcs present (2-arg)'); }
            return;
        }

        $this->dbg('maria-compat: installing BIN_TO_UUID/UUID_TO_BIN (2-arg)');

        $this->qexec("DROP FUNCTION IF EXISTS BIN_TO_UUID");
        $this->qexec("
            CREATE FUNCTION BIN_TO_UUID(b BINARY(16), swap TINYINT(1))
            RETURNS CHAR(36) DETERMINISTIC SQL SECURITY INVOKER
            RETURN LOWER(CONCAT_WS('-',
                IF(swap=1, SUBSTR(HEX(b),  9, 8), SUBSTR(HEX(b),  1, 8)),
                IF(swap=1, SUBSTR(HEX(b),  5, 4), SUBSTR(HEX(b),  9, 4)),
                IF(swap=1, SUBSTR(HEX(b),  1, 4), SUBSTR(HEX(b), 13, 4)),
                                    SUBSTR(HEX(b), 17, 4),
                                    SUBSTR(HEX(b), 21)
            ));
        ");

        $this->qexec("DROP FUNCTION IF EXISTS UUID_TO_BIN");
        $this->qexec("
            CREATE FUNCTION UUID_TO_BIN(u CHAR(36), swap TINYINT(1))
            RETURNS BINARY(16) DETERMINISTIC SQL SECURITY INVOKER
            RETURN UNHEX(
                IF(swap=1,
                    CONCAT(
                        SUBSTR(REPLACE(LOWER(u),'-',''), 13, 4),
                        SUBSTR(REPLACE(LOWER(u),'-',''),  9, 4),
                        SUBSTR(REPLACE(LOWER(u),'-',''),  1, 8),
                        SUBSTR(REPLACE(LOWER(u),'-',''), 17, 4),
                        SUBSTR(REPLACE(LOWER(u),'-',''), 21)
                    ),
                    REPLACE(LOWER(u),'-','')
                )
            );
        ");
    }

    private function traceViewAlgorithms(): void
    {
        if (getenv('BC_TRACE_VIEWS') !== '1') return;

        if ($this->dialect->isMysql() && !$this->isMariaDb()) {
            $views = $this->qfetchAll(
                "SELECT TABLE_NAME AS name
                FROM information_schema.VIEWS
                WHERE TABLE_SCHEMA = DATABASE()
                ORDER BY TABLE_NAME"
            );

            foreach ($views as $v) {
                $name = (string)$v['name'];
                try {
                    $ddl = (string)($this->showCreateView($name) ?? '');
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
            try {
                $rows = (array)$this->db->fetchAll(
                    "SELECT TABLE_NAME, ALGORITHM
                     FROM information_schema.VIEWS
                     WHERE TABLE_SCHEMA = DATABASE()
                     ORDER BY TABLE_NAME"
                );
                foreach ($rows as $r) {
                    error_log('[Installer][TRACE_VIEWS_ALG] ' . $r['TABLE_NAME'] . ' → ' . strtoupper((string)$r['ALGORITHM']));
                }
            } catch (\Throwable $e) {
                error_log('[Installer][TRACE_VIEWS_ALG][WARN] I_S.VIEWS read failed: ' . $e->getMessage());
            }
            return;
        }

        // Postgres – only log names
        if ($this->dialect->isPg()) {
            try {
                $rows = $this->qfetchAll(
                    "SELECT table_schema, table_name
                    FROM information_schema.views
                    WHERE table_schema = ANY (current_schemas(true))
                    ORDER BY table_schema, table_name"
                );
                foreach ($rows as $r) {
                    error_log('[Installer][TRACE_VIEWS_ALG] ' . $r['table_schema'] . '.' . $r['table_name'] . ' → N/A');
                }
            } catch (\Throwable $e) {
                error_log('[Installer][TRACE_VIEWS_ALG][WARN] I_S.views read failed: ' . $e->getMessage());
            }
        }
    }

    // --- Installer-level SQL wrappers -----------------------------------
    private function qexec(string $sql, array $meta = []): void
    {
        $t0 = \microtime(true);
        if ($this->traceSql) { $this->logSql($sql, null); }
        $kind   = $this->classify($sql, $objName);
        $meta   = ['component' => 'installer', 'op' => strtolower($kind), 'seq' => $this->runSeq]
                  + ($objName ? ['object' => $objName] : []) + $meta;

        if (method_exists($this->db, 'execWithMeta')) {
            $this->db->execWithMeta($sql, [], $meta);
        } else {
            $this->db->exec($sql);
        }
        $this->emitSqlTelemetry('exec', $sql, [], $meta, $t0);
    }

    private function qexecute(string $sql, array $params = [], array $meta = []): void
    {
        $t0 = \microtime(true);
        if ($this->traceSql) { $this->logSql($sql, $params); }
        $kind   = $this->classify($sql, $objName);
        $meta   = ['component' => 'installer', 'op' => strtolower($kind), 'seq' => $this->runSeq]
                  + ($objName ? ['object' => $objName] : []) + $meta;

        if (method_exists($this->db, 'execWithMeta')) {
            $this->db->execWithMeta($sql, $params, $meta);
        } else {
            $this->db->execute($sql, $params);
        }
        $this->emitSqlTelemetry('execute', $sql, $params, $meta, $t0);
    }

    // ---------- internal trace utilities ----------

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

        // helper to normalize "schema"."name" / `schema`.`name` / schema.name
        $clean = static function (string $x): string {
            return str_replace(['`','"'], '', $x);
        };

        // CREATE TABLE [schema.]table
        if (preg_match(
            '~^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?'
        . '((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)~i', $s, $m)) {
            $objName = $clean($m[1]);
            return 'CREATE TABLE';
        }

        // ALTER TABLE [schema.]table
        if (preg_match(
            '~^ALTER\s+TABLE\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)~i', $s, $m)) {
            $objName = $clean($m[1]);
            return 'ALTER TABLE';
        }

        // DROP TABLE [IF EXISTS] [schema.]table
        if (preg_match(
            '~^DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?'
        . '((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)~i', $s, $m)) {
            $objName = $clean($m[1]);
            return 'DROP TABLE';
        }

        // CREATE VIEW [schema.]view
        if (preg_match(
            '~^CREATE\s+(?:OR\s+REPLACE\s+)?'
        . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*'
        . '(?:MATERIALIZED\s+)?VIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)~i', $s, $m)) {
            $objName = $clean($m[1]);
            return (stripos($s, 'MATERIALIZED VIEW') !== false) ? 'CREATE MATERIALIZED VIEW' : 'CREATE VIEW';
        }

        // DROP VIEW [schema.]view
        if (preg_match(
            '~^DROP\s+(?:MATERIALIZED\s+)?VIEW\s+(?:IF\s+EXISTS\s+)?'
        . '((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)~i', $s, $m)) {
            $objName = $clean($m[1]);
            return (stripos($s, 'MATERIALIZED') !== false) ? 'DROP MATERIALIZED VIEW' : 'DROP VIEW';
        }

        // CREATE [UNIQUE] INDEX index ON [schema.]table
        if (preg_match(
            '~^CREATE\s+(?:UNIQUE\s+)?INDEX\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?).*?\s+ON\s+'
        . '((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)~i', $s, $m)) {
            $objName = $clean($m[1]) . ' ON ' . $clean($m[2]);
            return 'CREATE INDEX';
        }

        if (preg_match('~^BEGIN\b|^COMMIT\b|^ROLLBACK\b~i', $s)) return 'TXN';
        return 'SQL';
    }

    private function firstLine(string $sql): string {
        return \BlackCat\Database\Support\SqlPreview::firstLine($sql, 200);
    }

    private function findOrigin(): ?array
    {
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
        if ($this->mysqlVerCache !== null) { return $this->mysqlVerCache; }
        try {
            if (method_exists($this->db, 'serverVersion')) {
                $v = (string)($this->db->serverVersion() ?? $fallback);
            } else {
                $v = (string)($this->qfetchOne('SELECT VERSION()') ?? $fallback);
            }
            $num = (string)preg_replace('~^([0-9]+(?:\.[0-9]+){1,2}).*$~', '$1', $v);
            $this->mysqlVerCache = $num !== '' ? $num : $fallback;
            return $this->mysqlVerCache;
        } catch (\Throwable) {
            $this->mysqlVerCache = $fallback;
            return $this->mysqlVerCache;
        }
    }

    private function extractCreateViewStmtsRaw(string $rawSql): array {
        $out = [];
        $re  = '~CREATE\s+(?:OR\s+REPLACE\s+)?'
            . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*'
            . '(?:MATERIALIZED\s+)?VIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS\b.*?;~is';
        if (preg_match_all($re, $rawSql, $mm, PREG_SET_ORDER)) {
            foreach ($mm as $m) {
                $view = str_replace(['`','"'], '', $m[1]);  // allow schema.view
                $out[] = [$view, trim($m[0])];
            }
        }
        return $out;
    }

    /** Return true if a table exists in the current schema/database. */
    private function tableExists(?string $name): bool
    {
        if ($name === null || $name === '') return false;
        return \BlackCat\Database\Support\SchemaIntrospector::hasTable($this->db, $this->dialect, $name);
    }

    private function viewExists(string $name): bool
    {
        if ($name === '') return false;
        return \BlackCat\Database\Support\SchemaIntrospector::hasView($this->db, $this->dialect, $name);
    }

    /** Detailed list of missing module views (case-insensitive). */
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
     * Parse view names from 040_views.*.sql for the module.
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

    /** True if the module declares views and at least one is missing in DB. */
    private function moduleViewsMissing(ModuleInterface $m): bool
    {
        return $this->viewsMissingList($m) !== [];
    }

    /** Final list of schema files for the module (real paths + sha/len). */
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

    /** Collapse SQL into a single line (for local logs in Installer methods). */
    private function head(string $sql): string {
        return \BlackCat\Database\Support\SqlPreview::firstLine($sql, 200);
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

        $reg = $this->qfetch("SELECT version,checksum FROM _schema_registry WHERE module_name=:n", [':n'=>$m->name()]);
        $current  = $reg['version']  ?? null;
        $prevChk  = $reg['checksum'] ?? null;
        $newChk   = $this->computeChecksum($m);
        if ($this->verbose || $current === null || version_compare($current, $m->version(), '<')) {
            $this->dbg("installed={$current} checksum.prev=" . ($prevChk ?? 'null') . " checksum.new={$newChk}");
        }
        $forceRepair  = (getenv('BC_REPAIR') === '1');
        $didWork      = false;

        // --- decide install/upgrade with primary-table existence check ---
        $primaryTable = $m->table();
        $hasPrimaryTable = $primaryTable ? $this->tableExists($primaryTable) : true;

        if ($current === null || !$hasPrimaryTable) {
            $this->assertDependenciesInstalled($m);
            $reason = $current === null
                ? 'no-registry'
                : "missing-primary-table '{$primaryTable}'";
            $this->dbg("install() begin for {$m->name()} (reason={$reason})");
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

        // --- checksum drift (info used by decision below) ---
        $checksumDrift = ($prevChk !== null && $prevChk !== $newChk);

        // --- post-check indexes ---
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

        // --- NEW: PG auto-helpers (updated_at trigger, uuid_bin) ---
        if ($this->dialect->isPg() && ($didWork || $forceRepair)) {
            $this->ensurePgAutoHelpersForModule($m);
        }

        // --- robust decision whether to replay the VIEW script ---
        $viewsMissing = $this->moduleViewsMissing($m);
        $needsViews = $didWork || $forceRepair || $checksumDrift || $viewsMissing;

        $skipViews = (getenv('BC_INSTALLER_SKIP_VIEWS') === '1');
        if ($needsViews && !$skipViews) {
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
                $this->dbg("views: skip (" . ($skipViews ? 'env-skip' : 'no work, no force, no drift, all-present') . ")");
            }
        }

        // Optionally replay seeds (DML) after install/upgrade/smart drift
        if ($this->envOn('BC_RUN_SEEDS', false) && ($didWork || $forceRepair || $checksumDrift)) {
            $this->replaySeedScript($m);
        }

        // --- write version only after green post-check ---
        $this->upsertVersion($m, $newChk);
        $this->traceViewAlgorithmsFiltered($decl);

        $this->dlog("END   #{$seq} module={$m->name()}");
    }

    /** @param ModuleInterface[] $modules */
    public function installOrUpgradeAll(array $modules): void
    {
        $this->ensureRegistry();
        $ordered = $this->toposort($modules);
        $origFeature = getenv('BC_INCLUDE_FEATURE_VIEWS');
        // Disable feature views during the first pass to avoid dependency ordering issues
        putenv('BC_INCLUDE_FEATURE_VIEWS=0');
        foreach ($ordered as $m) {
            $this->installOrUpgrade($m);
        }
        if ($origFeature !== false) {
            putenv("BC_INCLUDE_FEATURE_VIEWS={$origFeature}");
        } else {
            putenv('BC_INCLUDE_FEATURE_VIEWS');
        }
        // Second pass: when feature views are enabled, replay views after all tables exist
        $includeFeatureViews = (getenv('BC_INCLUDE_FEATURE_VIEWS') === '1' || strtolower((string)getenv('BC_INCLUDE_FEATURE_VIEWS')) === 'true');
        if ($includeFeatureViews) {
            // Retryable pass: some feature views depend on other modules' views,
            // so keep going and re-attempt the failed modules after the rest are replayed.
            $pending = $ordered;
            $lastErr = null;
            for ($round = 1; $round <= 2 && $pending; $round++) {
                $next = [];
                foreach ($pending as $m) {
                    try {
                        $this->replayViewsScript($m);
                    } catch (\Throwable $e) {
                        $lastErr = $e;
                        $next[]  = $m;
                        $this->dbg('views-second-pass round ' . $round . ' failed for ' . $m->name() . ': ' . $e->getMessage());
                    }
                }
                $pending = $next;
            }
            if ($pending && $lastErr !== null) {
                throw $lastErr;
            }
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

    // ---------- internal helpers ----------

    private function getVersion(string $name): ?string
    {
        $sql = "SELECT version FROM _schema_registry WHERE module_name = :name";
        $val = $this->db->fetchOne($sql, [':name' => $name]);
        return $val !== null ? (string)$val : null;
    }

    private function upsertVersion(ModuleInterface $m, string $checksum): void
    {
        // shared parameters
        $params = [
            ':name'     => $m->name(),
            ':version'  => $m->version(),
            ':checksum' => $checksum,
        ];

        if ($this->dialect->isMysql()) {
            // Varianta s aliasem (bez VALUES()) — pro MySQL 8.0.20+
            $sqlAlias = "INSERT INTO _schema_registry AS _new (module_name,version,checksum)
                        VALUES (:name,:version,:checksum)
                        ON DUPLICATE KEY UPDATE
                            version  = _new.version,
                            checksum = _new.checksum";

            // VALUES() variant — for MariaDB and older MySQL
            $sqlValues = "INSERT INTO _schema_registry (module_name,version,checksum)
                        VALUES (:name,:version,:checksum)
                        ON DUPLICATE KEY UPDATE
                            version  = VALUES(version),
                            checksum = VALUES(checksum)";

            // Branch based on platform/version
            $useAlias = false;
            if (!$this->isMariaDb()) {
                // MySQL only: VALUES() removed from UPDATE since 8.0.20
                $useAlias = \version_compare($this->mysqlVersionNumber(), '8.0.20', '>=');
            }

            $primary  = $useAlias ? $sqlAlias  : $sqlValues;
            $fallback = $useAlias ? $sqlValues : $sqlAlias;

            try {
                $this->qexecute($primary, $params);
            } catch (\Throwable $e) {
                if ($this->diagEnabled()) {
                    $code = $this->pdoErrorCode($e);
                    $this->dbg('upsertVersion: primary variant failed'
                        . ($code !== null ? " (code={$code})" : '')
                        . ' → retrying fallback');
                }
                // final attempt – let it bubble up otherwise
                $this->qexecute($fallback, $params);
            }
            return;
        }

        // PostgreSQL
        $col = Ident::q($this->db, 'module_name'); // cosmetic quoting consistency
        $sql = "INSERT INTO _schema_registry(module_name,version,checksum)
                VALUES(:name,:version,:checksum)
                ON CONFLICT ($col)
                DO UPDATE SET
                    version  = EXCLUDED.version,
                    checksum = EXCLUDED.checksum";
        $this->qexecute($sql, $params);
    }
    
    /**
     * Replay only the index script 020_indexes.<dial>.sql for the module.
     */
    private function replayIndexScript(ModuleInterface $m): void
    {
        $dir  = $this->schemaDirBesideSrc($m);
        $dial = $this->dialect->isMysql() ? 'mysql' : 'postgres';
        $this->dbg("indexes: scanning in {$dir} (dialect={$dial})");

        $candidates = glob($dir . '/020_indexes.' . $dial . '.sql') ?: [];

        foreach ($candidates as $path) {
            $this->dbg("indexes: file " . basename($path) . " → " . realpath($path));
            $sql = @file_get_contents($path);
            if ($sql === false) { continue; }

            $sql   = (string)$sql;
            $sql   = $this->stripSqlComments($sql);
            $stmts = SqlSplitter::split($sql, $this->dialect);
            foreach ($stmts as $stmt) {
                $stmt = trim($stmt);
                if ($stmt !== '') {
                    if (!preg_match('~^(CREATE\s+INDEX|CREATE\s+UNIQUE\s+INDEX|ALTER\s+TABLE|DROP\s+INDEX)~i', $stmt)) {
                        continue;
                    }
                    if (!$this->traceSql && $this->diagEnabled()) {
                        $this->dbg("indexes: exec " . $this->head($stmt));
                    }
                    Retry::runAdvanced(
                        fn() => $this->qexec($stmt),
                        attempts: 3,
                        initialMs: 25,
                        factor: 2.0,
                        maxMs: 1000,
                        jitter: 'full',
                        onRetry: function (int $attempt, \Throwable $e, int $sleepMs) use ($stmt): void {
                            if ($this->diagEnabled()) {
                                $code = $this->pdoErrorCode($e);
                                $this->dbg(
                                    'indexes: retry#' . $attempt
                                    . ' sleep=' . $sleepMs . 'ms'
                                    . ($code !== null ? ' code=' . $code : '')
                                    . ' err=' . substr($e->getMessage(), 0, 200)
                                    . ' head=' . $this->head($stmt)
                                );
                            }
                        }
                    );
                }
            }
        }
    }
    
    private function replayViewsScript(ModuleInterface $m): void
    {
        $dir  = $this->schemaDirBesideSrc($m);
        $dial = $this->dialect->isMysql() ? 'mysql' : 'postgres';
        $targetView = strtolower((string)$m::contractView());
        $includeFeatureViews = (getenv('BC_INCLUDE_FEATURE_VIEWS') === '1' || strtolower((string)getenv('BC_INCLUDE_FEATURE_VIEWS')) === 'true');
        $filterByContract = ($targetView !== '' && !$includeFeatureViews);

        if ($this->traceFiles) { $this->dbg("views: scanning in {$dir} (dialect={$dial})"); }

        $cands = glob($dir . '/040_views.' . $dial . '.sql') ?: [];
        if (!$cands) { $this->dlog("views: no candidates in {$dir} for dial={$dial}"); return; }
        foreach ($cands as $file) {
            if ($this->traceFiles) { $this->dbg("views: file " . basename($file) . " → " . realpath($file)); }

            $raw = (string)@file_get_contents($file);
            if ($raw === '') { continue; }
            $raw = ltrim($raw, "\xEF\xBB\xBF");

            // Skip feature-layer views unless explicitly enabled
            if (!$includeFeatureViews && stripos($raw, 'schema-views-feature-') !== false) {
                $this->dlog('views: skip feature layer (BC_INCLUDE_FEATURE_VIEWS=0) for ' . basename($file));
                continue;
            }

            $sqlNoComments = $this->stripSqlComments($raw);

            $stmts     = \BlackCat\Database\Support\SqlSplitter::split($sqlNoComments, $this->dialect);
            $execCount = 0; $ignored = 0;

            foreach ($stmts as $stmt) {
                $stmt = trim($stmt);
                if ($stmt === '') { continue; }

                if (preg_match('~^DROP\s+VIEW\b~i', $stmt)) {
                    $ignored++;
                    continue;
                }
                if ($filterByContract) {
                    if (preg_match('~\bVIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS\b~i', $stmt, $mm)) {
                        $vraw  = $mm[1];
                        $vname = strtolower(str_replace(['`','"'],'',$vraw));
                        $vbase = str_contains($vname,'.') ? substr($vname, (int)strrpos($vname,'.')+1) : $vname;
                        if ($vbase !== $targetView) { $ignored++; continue; }
                    } else {
                        $ignored++; 
                        continue;
                    }
                }

                if (preg_match(
                    '~^CREATE\s+(?:OR\s+REPLACE\s+)?'
                  . '(?:ALGORITHM\s*=\s*\w+\s+|DEFINER\s*=\s*(?:`[^`]+`@`[^`]+`|[^ \t]+)\s+|SQL\s+SECURITY\s+\w+\s+)*'
                  . '(?:MATERIALIZED\s+)?VIEW\b~i',
                    $stmt
                )) {
                    if (!$this->traceSql && $this->diagEnabled()) { $this->dbg("views: guarded " . $this->head($stmt)); }
                    $stmt = $this->normalizeCreateViewDirectives($stmt);
                    if ($stmt === '') { $ignored++; continue; }
                    if ($this->dialect->isPg()) {
                        // PostgreSQL: drop-and-create to avoid column rename errors on existing views
                        $dropName = $targetView;
                        if (!$dropName && preg_match('~\bVIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS\b~i', $stmt, $mm)) {
                            $dropName = str_replace(['`','"'],'',$mm[1]);
                        }
                        if ($dropName) {
                            try { $this->qexec('DROP VIEW IF EXISTS ' . $dropName); } catch (\Throwable) {}
                        }
                        $this->qexec($stmt);
                    } else {
                        $this->ddlGuard->applyCreateView($stmt, [
                            'lockTimeoutSec'    => (int)(getenv('BC_VIEW_LOCK_TIMEOUT') ?: 10),
                            'retries'           => (int)(getenv('BC_INSTALLER_VIEW_RETRIES') ?: 3),
                            'fenceMs'           => (int)(getenv('BC_VIEW_FENCE_MS') ?: 600),
                            'dropFirst'         => true,
                            'normalizeOrReplace'=> true,
                        ]);
                    }
                    $execCount++;
                    continue;
                }

                $ignored++;
            }

            if ($execCount === 0) {
                $fb = $this->extractCreateViewStmtsRaw($raw);
                if ($fb) {
                    $this->dbg("views: fallback-extractor executing " . count($fb) . " CREATE VIEW stmt(s)");
                    foreach ($fb as [$vname, $stmt]) {
                        $baseRaw = preg_replace('~^.*\.~','', str_replace(['`','"'],'',$vname));
                        $vbase = strtolower(\is_string($baseRaw) ? $baseRaw : (string)$vname);
                        if ($filterByContract && $vbase !== $targetView) { $ignored++; continue; }
                        $stmt = $this->normalizeCreateViewDirectives($stmt);
                        if ($stmt === '') { $ignored++; continue; }
                        if (!$this->traceSql && $this->diagEnabled()) { $this->dbg("views: guarded-fallback " . $this->head($stmt)); }
                        if ($this->dialect->isPg()) {
                            $dropName = $targetView;
                            if (!$dropName && preg_match('~\bVIEW\s+((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)\s+AS\b~i', $stmt, $mm)) {
                                $dropName = str_replace(['`','"'],'',$mm[1]);
                            }
                            if ($dropName) { try { $this->qexec('DROP VIEW IF EXISTS ' . $dropName); } catch (\Throwable) {} }
                            $this->qexec($stmt);
                        } else {
                            $this->ddlGuard->applyCreateView($stmt, [
                                'lockTimeoutSec'     => (int)(getenv('BC_VIEW_LOCK_TIMEOUT') ?: 10),
                                'retries'            => (int)(getenv('BC_INSTALLER_VIEW_RETRIES') ?: 3),
                                'fenceMs'            => (int)(getenv('BC_VIEW_FENCE_MS') ?: 600),
                                'dropFirst'          => true,
                                'normalizeOrReplace' => true,
                            ]);
                        }
                        $execCount++;
                    }
                } else {
                    $this->dbg("views: fallback-extractor found 0 CREATE VIEW stmt(s)");
                }
            }

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

    /** Vytiskne SHOW CREATE VIEW/pg_get_viewdef ... */
    private function dumpViewDefinitions(array $names): void
    {
        foreach ($names as $name) {
            try {
                if ($this->dialect->isMysql()) {
                    $ddl = (string)($this->showCreateView($name) ?? '');
                    $hash = $ddl !== '' ? substr(hash('sha256', $ddl), 0, 12) : 'null';
                    $head = substr((string)preg_replace('~\\s+~',' ', $ddl), 0, 160);
                    $this->dlog("SHOW CREATE VIEW " . $name . " -> hash=" . $hash . " head=" . $head);
                } else {
                    $row = $this->qfetch(
                        "SELECT n.nspname AS s, c.relname AS n, pg_get_viewdef(c.oid, true) AS def
                         FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                         WHERE c.relkind='v' AND lower(c.relname)=lower(:v) AND n.nspname = ANY (current_schemas(true))",
                        [':v'=>$name]
                    );
                    $ddl = (string)($row['def'] ?? '');
                    $hash = $ddl !== '' ? substr(hash('sha256', $ddl), 0, 12) : 'null';
                    $head = substr((string)preg_replace('~\\s+~',' ', $ddl), 0, 160);
                    $this->dlog("pg_get_viewdef " . $name . " -> hash=" . $hash . " head=" . $head);
                }
            } catch (\Throwable $e) {
                $this->dlog("viewDef ERR " . $name . " -> " . $e->getMessage());
            }
        }
    }

    /** Safe consistent SHOW CREATE VIEW (MySQL/MariaDB); returns null on PG. */
    private function showCreateView(string $name): ?string
    {
        if (!$this->dialect->isMysql()) return null;

        $sql = 'SHOW CREATE VIEW ' . Ident::qi($this->db, $name);
        try {
            $row = $this->db->fetchRowWithMeta($sql, [], ['component' => 'installer', 'op' => 'show_create_view', 'view' => $name]) ?? [];
            foreach (['Create View', 'Create View ', 'Create view', 1] as $k) {
                if (array_key_exists((string)$k, $row)) {
                    return (string)$row[(string)$k];
                }
            }
            $vals = array_values($row);
            return isset($vals[1]) ? (string)$vals[1] : null;
        } catch (\Throwable) {
            return null;
        }
    }

    /** Filtered listing of algorithms ... */
    private function traceViewAlgorithmsFiltered(array $onlyThese): void
    {
        if (getenv('BC_TRACE_VIEWS') !== '1') return;
        if (!$onlyThese) { $this->traceViewAlgorithms(); return; }

        try {
            if ($this->dialect->isMysql() && !$this->isMariaDb()) {
                foreach ($onlyThese as $name) {
                    try {
                        $ddl = (string)($this->showCreateView($name) ?? '');
                        $alg = 'UNKNOWN';
                        if (preg_match('~\bALGORITHM\s*=\s*(UNDEFINED|MERGE|TEMPTABLE)\b~i', $ddl, $m)) {
                            $alg = strtoupper($m[1]);
                        }
                        error_log('[Installer][TRACE_VIEWS_ALG] ' . $name . ' -> ' . $alg);
                    } catch (\Throwable $e) {
                        error_log('[Installer][TRACE_VIEWS_ALG][WARN] SHOW CREATE VIEW ' . $name . ' failed: ' . $e->getMessage());
                    }
                }
                return;
            }

            if ($this->isMariaDb()) {
                $names = array_values(array_unique(array_map('strtolower', $onlyThese)));

                $placeholders = [];
                $params = [];
                foreach ($names as $i => $n) {
                    $ph = ":v{$i}";
                    $placeholders[] = $ph;
                    $params[$ph] = $n;
                }

                $sql = "
                    SELECT TABLE_NAME, ALGORITHM
                    FROM information_schema.VIEWS
                    WHERE TABLE_SCHEMA = DATABASE()
                    AND LOWER(TABLE_NAME) IN (".implode(',', $placeholders).")
                    ORDER BY TABLE_NAME
                ";
                $rows = $this->qfetchAll($sql, $params);
                foreach ($rows as $r) {
                    error_log('[Installer][TRACE_VIEWS_ALG] ' . $r['TABLE_NAME'] . ' -> ' . strtoupper((string)$r['ALGORITHM']));
                }
                return;
            }

        } catch (\Throwable $e) {
            error_log('[Installer][TRACE_VIEWS_ALG][WARN] filtered failed: ' . $e->getMessage());
        }

        $this->traceViewAlgorithms();
    }

    /**
     * Replay only the seed script 050_seeds.<dial>.sql (DML). Activated via BC_RUN_SEEDS=1.
     */
    private function replaySeedScript(ModuleInterface $m): void
    {
        $dir  = $this->schemaDirBesideSrc($m);
        $dial = $this->dialect->isMysql() ? 'mysql' : 'postgres';
        $cands = glob($dir . '/050_seeds.' . $dial . '.sql') ?: [];
        if (!$cands) { $this->dlog("seeds: no candidates in {$dir} for dial={$dial}"); return; }

        foreach ($cands as $file) {
            $this->dbg("seeds: file " . basename($file) . " → " . realpath($file));
            $raw = (string)@file_get_contents($file);
            if ($raw === '') continue;
            $sql = $this->stripSqlComments($raw);
            $stmts = SqlSplitter::split($sql, $this->dialect);
            $exec = 0;
            foreach ($stmts as $stmt) {
                $stmt = trim($stmt);
                if ($stmt === '') continue;
                if (!$this->traceSql && $this->diagEnabled()) { $this->dbg("seeds: exec " . $this->head($stmt)); }
                // DML/DQL – use execute; DDL passes as well
                $this->qexec($stmt);
                $exec++;
            }
            $this->dbg("seeds: executed {$exec} stmts");
        }
    }
    public function replayViews(bool $force = false): void
    {
        // no-op – kept for compatibility
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

        usort($list, fn($a,$b) => strcmp($a['name'], $b['name']));

        $payload = [
            'info'    => $m->info(),
            'dialect' => $this->dialect->value,
            'files'   => $list,
        ];

        $payloadJson = json_encode($payload, JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE) ?: '';
        return hash('sha256', $payloadJson);
    }

    /** Pull schema files only for the current dialect (supports . and _). */
    private function schemaFilesFor(ModuleInterface $m, SqlDialect $dialect): array
    {
        $dir = $this->schemaDirBesideSrc($m);
        $d   = $dialect->isMysql() ? 'mysql' : 'postgres';

        // podporuj jak 001_xxx.mysql.sql, tak 001_xxx_mysql.sql
        $all = array_merge(
            glob($dir . '/*.' . $d . '.sql') ?: [],
            glob($dir . '/*_' . $d . '.sql') ?: []
        );

        $all = array_values(array_filter($all, function (string $path) use ($d): bool {
            $bn = basename($path);
            return (bool)preg_match('~^(\d{3})_[a-z0-9_]+[._]' . preg_quote($d, '~') . '\.sql$~i', $bn);
        }));

        usort($all, function (string $a, string $b): int {
            $ba = basename($a); $bb = basename($b);
            preg_match('~^(\d{3})_~', $ba, $ma);
            preg_match('~^(\d{3})_~', $bb, $mb);
            $na = isset($ma[1]) ? (int)$ma[1] : 0;
            $nb = isset($mb[1]) ? (int)$mb[1] : 0;
            return ($na !== $nb) ? ($na <=> $nb) : strcasecmp($ba, $bb);
        });

        return array_map(fn($p) => realpath($p) ?: $p, $all);
    }

    /** Kanonizace SQL: ... */
    private function canonicalizeSql(string $sql, SqlDialect $dialect): string
    {
        if (strncmp($sql, "\xEF\xBB\xBF", 3) === 0) {
            $sql = substr($sql, 3);
        }

        $sql = preg_replace("~\r\n?~", "\n", $sql) ?? $sql;
        $sql = preg_replace('~[ \t]+$~m', '', $sql) ?? $sql;

        $sql = $this->stripSqlComments($sql);

        if ($dialect->isMysql()) {
            $sql = preg_replace('~\bDEFINER\s*=\s*[^ ]+~i', '', $sql) ?? $sql;
            $sql = preg_replace('~^\s*DELIMITER\s+\S+.*$~mi', '', $sql) ?? $sql;
        } else {
            $sql = preg_replace('~^\s*SET\s+search_path\s+.*$~mi', '', $sql) ?? $sql;
        }

        $sql = preg_replace('~\bCREATE\s+OR\s+REPLACE\b~i', 'CREATE', $sql) ?? $sql;

        $sql = preg_replace("~\n{3,}~", "\n\n", $sql) ?? $sql;
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

    private function qfetch(string $sql, array $params = [], array $meta = []): array {
        $t0 = \microtime(true);
        if ($this->traceSql) { $this->logSql($sql, $params); }
        $kind = $this->classify($sql, $objName);
        $meta = ['component' => 'installer', 'op' => strtolower($kind) . ':fetch', 'seq' => $this->runSeq]
                + ($objName ? ['object' => $objName] : []) + $meta;
        $result = $this->db->fetchRowWithMeta($sql, $params, $meta) ?? [];
        $this->emitSqlTelemetry('fetch', $sql, $params, $meta, $t0);
        return $result;
    }

    private function qfetchAll(string $sql, array $params = [], array $meta = []): array {
        $t0 = \microtime(true);
        if ($this->traceSql) { $this->logSql($sql, $params); }
        $kind = $this->classify($sql, $objName);
        $meta = ['component' => 'installer', 'op' => strtolower($kind) . ':fetchAll', 'seq' => $this->runSeq]
                + ($objName ? ['object' => $objName] : []) + $meta;
        $rows = (array)$this->db->fetchAllWithMeta($sql, $params, $meta);
        $this->emitSqlTelemetry('fetchAll', $sql, $params, $meta, $t0);
        return $rows;
    }

    private function qfetchOne(string $sql, array $params = [], array $meta = []): mixed {
        $t0 = \microtime(true);
        if ($this->traceSql) { $this->logSql($sql, $params); }
        $kind = $this->classify($sql, $objName);
        $meta = ['component' => 'installer', 'op' => strtolower($kind) . ':fetchOne', 'seq' => $this->runSeq]
                + ($objName ? ['object' => $objName] : []) + $meta;
        $value = $this->db->fetchValueWithMeta($sql, $params, null, $meta);
        $this->emitSqlTelemetry('fetchOne', $sql, $params, $meta, $t0);
        return $value;
    }

    // -------------------- NEW PG AUTO-HELPERS --------------------

    /** true/false from env with reasonable defaults (1/true/on) */
    private function envOn(string $name, bool $default = true): bool
    {
        $v = getenv($name);
        if ($v === false || $v === '') return $default;
        return in_array(strtolower((string)$v), ['1','true','yes','on','y'], true);
    }

    private function emitSqlTelemetry(string $op, string $sql, ?array $params, array $meta, float $t0): void
    {
        $sample = $this->sqlTelemetrySample ??= $this->detectInstallerSqlSample();
        if ($sample <= 0.0) {
            return;
        }
        $ctx = [
            'component' => 'installer',
            'op'        => $op,
            'object'    => $meta['object'] ?? null,
            'seq'       => $meta['seq'] ?? null,
            'ms'        => Observability::ms($t0),
            'sql_head'  => $this->firstLine($sql),
            'params'    => $params ? Observability::paramsShape($params) : [],
            'sample'    => $sample,
        ];
        try {
            if (Observability::shouldSample($ctx)) {
                Telemetry::debug('installer.sql', $ctx);
            }
        } catch (\Throwable) {
            // telemetry is best-effort
        }
    }

    private function detectInstallerSqlSample(): float
    {
        $env = \getenv('BC_INSTALLER_SQL_SAMPLE');
        if ($env === false || $env === '') {
            return 0.0;
        }
        $rate = (float)$env;
        return ($rate > 0 && $rate <= 1) ? $rate : 0.0;
    }

    /** Run PgCompat.install() once (bc_compat schema, functions, trigger functions) */
    private function ensurePgCompatInstalled(): void
    {
        if ($this->pgCompatEnsured || !$this->dialect->isPg()) return;
        try {
            (new PgCompat($this->db))->install();
            $this->pgCompatEnsured = true;
            $this->dbg('pg-compat: installed (bc_compat schema ready)');
        } catch (\Throwable $e) {
            $this->dbg('pg-compat: install failed: ' . $e->getMessage());
            throw $e;
        }
    }

    /** Module table list: prefer $m->tables(), then parse from schema files, then primary table() */
    private function tablesForModule(ModuleInterface $m): array
    {
        // 1) pokud modul poskytuje seznam tabulek
        if (method_exists($m, 'tables')) {
            $callable = [$m, 'tables'];
            $list = array_filter(array_map('strval', (array)\call_user_func($callable)));
            if ($list) return array_values(array_unique($list));
        }

        // 2) parse CREATE TABLE from *.sql for the dialect
        $tables = [];
        foreach ($this->schemaFilesFor($m, $this->dialect) as $file) {
            $raw = (string)@file_get_contents($file);
            if ($raw === '') continue;
            $sql = $this->stripSqlComments($raw);
            if (preg_match_all(
                '~CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?((?:`?"?[A-Za-z0-9_]+`?"?\.)?`?"?[A-Za-z0-9_]+`?"?)~i',
                $sql, $mm
            )) {
                foreach ($mm[1] as $fqn) {
                    $name = strtolower(str_replace(['`','"'], '', $fqn));
                    $base = str_contains($name, '.') ? substr($name, strrpos($name,'.')+1) : $name;
                    $tables[$base] = $base;
                }
            }
        }

        // 3) fallback na primary table()
        $pt = $m->table();
        if ($pt) { $tables[strtolower($pt)] = strtolower($pt); }

        return array_values($tables);
    }

    /** Return true if the table contains the given column (dialect-aware) */
    private function tableHasColumn(string $table, string $column): bool
    {
        if ($this->dialect->isPg()) {
            $sql = "SELECT 1
                    FROM information_schema.columns
                    WHERE table_schema = ANY (current_schemas(true))
                      AND lower(table_name)=lower(:t)
                      AND lower(column_name)=lower(:c)
                    LIMIT 1";
            return (bool)$this->qfetchOne($sql, [':t'=>$table, ':c'=>$column]);
        }
        // MySQL/MariaDB
        $sql = "SELECT 1
                FROM information_schema.columns
                WHERE table_schema = DATABASE()
                  AND lower(table_name)=lower(:t)
                  AND lower(column_name)=lower(:c)
                LIMIT 1";
        return (bool)$this->qfetchOne($sql, [':t'=>$table, ':c'=>$column]);
    }

    /** For a module (PG) ensure updated_at trigger and uuid_bin computed column */
    private function ensurePgAutoHelpersForModule(ModuleInterface $m): void
    {
        if (!$this->dialect->isPg()) return;

        $enableUpdatedAt = $this->envOn('BC_PG_AUTO_UPDATED_AT', true);
        $enableUuidBin   = $this->envOn('BC_PG_UUID_BIN', true);

        if (!$enableUpdatedAt && !$enableUuidBin) {
            $this->dbg('pg-auto: skipped (both features disabled by env)');
            return;
        }

        $this->ensurePgCompatInstalled();
        $pg = new PgCompat($this->db);

        $tables = $this->tablesForModule($m);
        if (!$tables) return;

        foreach ($tables as $t) {
            // updated_at trigger
            if ($enableUpdatedAt && $this->tableHasColumn($t, 'updated_at')) {
                try {
                    $pg->ensureUpdatedAtTrigger($t, 'updated_at');
                    $this->dbg("pg-auto: updated_at trigger ensured for {$t}");
                } catch (\Throwable $e) {
                    $this->dbg("pg-auto: updated_at trigger failed for {$t}: " . $e->getMessage());
                    if (getenv('BC_INSTALLER_STRICT_PG_AUTO') === '1') { throw $e; }
                }
            }

            // uuid_bin computed + unique index
            if ($enableUuidBin && $this->tableHasColumn($t, 'uuid')) {
                try {
                    $pg->ensureUuidBinComputed($t, 'uuid', 'uuid_bin');
                    $this->dbg("pg-auto: uuid_bin ensured for {$t}");
                } catch (\Throwable $e) {
                    $this->dbg("pg-auto: uuid_bin failed for {$t}: " . $e->getMessage());
                    if (getenv('BC_INSTALLER_STRICT_PG_AUTO') === '1') { throw $e; }
                }
            }
        }
    }
}
