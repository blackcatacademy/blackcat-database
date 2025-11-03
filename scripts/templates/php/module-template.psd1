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

    private function qi(SqlDialect $d, string $ident): string {
        $parts = explode('.', $ident);
        if ($d->isMysql()) {
            return implode('.', array_map(fn($p) => "`$p`", $parts));
        }
        return implode('.', array_map(fn($p) => '"' . $p . '"', $parts));
    }

    private function stTrace(): bool { return getenv('BC_STATUS_TRACE') === '1'; }
    private function stLog(string $tag, array $ctx = []): void {
        if (!$this->stTrace()) return;
        // jednoduché JSON bez uvozovek, ať se to čte v logu
        foreach ($ctx as $k=>$v) { if (is_array($v)) $ctx[$k] = array_values($v); }
        error_log('[STATUS]['.$tag.'] '.json_encode($ctx, JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE));
    }

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

        $files = array_merge(
            glob($dir.'/*.'. $dial .'.sql') ?: [],
            glob($dir.'/*_' . $dial .'.sql') ?: []
        );
        $files = array_values(array_unique($files));
        usort($files, static function($a, $b) {
            $pa = (int)preg_replace('~^.*?/([0-9]{3})_.*$~', '$1', $a);
            $pb = (int)preg_replace('~^.*?/([0-9]{3})_.*$~', '$1', $b);
            return $pa <=> $pb ?: strcmp($a, $b);
        });

        foreach ($files as $path) {
            $this->execSqlFileStreamed($db, $path, $d);
        }
        // --- Zajisti kontraktní view ---
        $table = $this->qi($d, $this->table());
        $view  = $this->qi($d, self::contractView());

        if ($d->isMysql()) {
            $db->exec("DROP VIEW IF EXISTS {$view}");
            $db->exec("CREATE VIEW {$view} AS SELECT * FROM {$table}");
        } else {
            $db->exec("DROP VIEW IF EXISTS {$view} CASCADE");
            $db->exec("CREATE VIEW {$view} AS SELECT * FROM {$table}");
        }
    }

    private function execSqlFileStreamed(Database $db, string $path, SqlDialect $d): void {
        $fh = @fopen($path, 'rb');
        if ($fh === false) { return; }
        $buf = '';
        while (!feof($fh)) {
            $chunk = fread($fh, 65536);
            if ($chunk === false) { break; }
            $buf .= $chunk;

            foreach ($this->splitStatements($buf, $d) as $stmt) {
                if ($stmt !== '') { $this->safeExec($db, $stmt); }
            }
            // zbytek neúplného statementu v $buf
            $buf = $this->remainder;
        }
        fclose($fh);
        $tail = trim($buf);
        if ($tail !== '') { $this->safeExec($db, $tail); }
        $this->remainder = ''; // ← důležité: nepropaguj zbytek do dalšího souboru
    }

    private string $remainder = '';

    /**
     * Rozdělí buffer na kompletní SQL statementy (ignoruje ; uvnitř stringů/dollar-quotů).
     * Jednoduchý state machine pro běžné DDL.
     */
    private function splitStatements(string $buf, SqlDialect $d): array {
        $out = [];
        $state = 'code';
        $q = '';
        $i = 0;
        $start = 0;
        $len = strlen($buf);

        // přidej zbytek z minula
        if ($this->remainder !== '') {
            $buf = $this->remainder . $buf;
            $len = strlen($buf);
            $this->remainder = '';
        }

        while ($i < $len) {
            $ch = $buf[$i];
            $ch2 = ($i+1 < $len) ? $buf[$i+1] : '';

            if ($state === 'code') {
                if ($ch === "'" || $ch === '"') { $state='str'; $q=$ch; $i++; continue; }
                if (!$d->isMysql() && $ch === '$') {
                    // PG dollar-quote: $tag$ ... $tag$
                    if (preg_match('/\G\$([a-zA-Z0-9_]*)\$/A', substr($buf, $i), $m)) {
                        $state = 'dollar';
                        $q = '$'.$m[1].'$';
                        $i += strlen($q);
                        continue;
                    }
                }
                if ($ch === '-' && $ch2 === '-') { // -- comment
                    $nl = strpos($buf, "\n", $i+2); $i = ($nl === false) ? $len : $nl+1; continue;
                }
                if ($ch === '/' && $ch2 === '*') { // /* comment */
                    $end = strpos($buf, '*/', $i+2); $i = ($end === false) ? $len : $end+2; continue;
                }
                if ($ch === ';') {
                    $out[] = trim(substr($buf, $start, $i - $start));
                    $start = $i+1;
                }
                $i++; continue;
            }

            if ($state === 'str') {
                if ($ch === '\\') { $i += 2; continue; } // escape
                if ($ch === $q) { $state = 'code'; $i++; continue; }
                $i++; continue;
            }

            if ($state === 'dollar') {
                if (substr($buf, $i, strlen($q)) === $q) {
                    $i += strlen($q);
                    $state = 'code';
                    continue;
                }
                $i++; continue;
            }
        }

        // zbytek ulož
        $this->remainder = substr($buf, $start);
        return array_filter($out, static fn($s) => $s !== '');
    }

    /** DDL s tolerancí duplicít pro idempotenci. */
    private function safeExec(Database $db, string $sql): void {
        $sqlTrim = trim($sql);
        if ($sqlTrim === '') { return; }

        // --- Idempotentní CHECK: DROP před ADD ---
        if (preg_match('~(?is)^ALTER\s+TABLE\s+([`"]?[\w\.]+[`"]?)\s+ADD\s+CONSTRAINT\s+([`"]?[\w]+[`"]?)\s+CHECK\s*\(~', $sqlTrim, $m)) {
            $table = $m[1];
            $name  = $m[2];

            $tabName = trim($table, '`"');
            $chkName = trim($name,  '`"');

            if ($db->isMysql()) {
                // předcheck existence CHECK constraintu (MySQL/MariaDB)
                $exists = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                    WHERE CONSTRAINT_SCHEMA = DATABASE()
                    AND TABLE_NAME = :t
                    AND CONSTRAINT_NAME = :c
                    AND CONSTRAINT_TYPE = 'CHECK'",
                    [':t'=>$tabName, ':c'=>$chkName]
                ) > 0;

                if ($exists) {
                    // Rozlišení MariaDB vs. Oracle MySQL
                    $isMaria = false;
                    try {
                        $vc = (string)($db->fetchOne("SELECT @@version_comment") ?? '');
                        if ($vc === '') { $vc = (string)($db->fetchOne("SELECT VERSION()") ?? ''); }
                        $isMaria = stripos($vc, 'mariadb') !== false;
                    } catch (\Throwable) {}

                    try {
                        if ($isMaria) {
                            // MariaDB preferuje DROP CONSTRAINT
                            $db->exec("ALTER TABLE $table DROP CONSTRAINT $name");
                        } else {
                            // Oracle MySQL: DROP CHECK
                            $db->exec("ALTER TABLE $table DROP CHECK $name");
                        }
                    } catch (\Throwable $e1) {
                        // Fallback – zkus opačnou syntaxi (pro případ odchylek mezi versíemi)
                        try {
                            $db->exec("ALTER TABLE $table DROP CHECK $name");
                        } catch (\Throwable $e2) {
                            try {
                                $db->exec("ALTER TABLE $table DROP CONSTRAINT $name");
                            } catch (\Throwable $e3) {
                                throw $e1; // vrať původní chybu
                            }
                        }
                    }
                }
            } else {
                // Postgres: má IF EXISTS
                $db->exec("ALTER TABLE $table DROP CONSTRAINT IF EXISTS $name");
            }
            // pak teprve ADD …
        }

        try {
            $db->exec($sqlTrim);
        } catch (\BlackCat\Core\DatabaseException $e) {
            $prev      = $e->getPrevious();
            $msgOuter  = strtolower((string)$e->getMessage());                 // např. "exec failed"
            $msgInner  = strtolower($prev instanceof \PDOException ? (string)$prev->getMessage() : '');
            $msgAll    = trim($msgOuter . ' ' . $msgInner);                     // spojíme obě zprávy
            $isMy      = $db->isMysql();

            $sqlstate  = ($prev instanceof \PDOException) ? (string)($prev->errorInfo[0] ?? '') : '';
            $code      = ($prev instanceof \PDOException) ? (int)($prev->errorInfo[1] ?? 0) : 0;

            $tolerate = false;
            if ($isMy) {
                // původní whitelist MySQL chyb
                $tolerate = in_array($code, [1050,1051,1060,1061,1091,1826,3822], true)
                            || str_contains($msgAll, 'already exists')
                            || str_contains($msgAll, 'duplicate')
                            || str_contains($msgAll, 'cannot drop index')
                            || str_contains($msgAll, 'cannot add foreign key constraint');

                // cíleně: MariaDB/MySQL ALTER TABLE rebuild → 1005 + errno: 121 "Duplicate key on write or update"
                if (!$tolerate && $code === 1005 && (str_contains($msgAll, 'errno: 121') || str_contains($msgAll, 'duplicate key on write or update'))) {
                    $tolerate = true;
                }
            } else {
                $tolerate = in_array($sqlstate, ['42P07','42710','42701'], true)
                            || str_contains($msgAll, 'already exists');
            }

            if ($tolerate) {
                // volitelný trace – jen když máš BC_STATUS_TRACE=1
                if (method_exists($this, 'stLog') && getenv('BC_STATUS_TRACE') === '1') {
                    $this->stLog('SAFE.TOLERATE', ['code'=>$code, 'sqlstate'=>$sqlstate, 'msg'=>$msgAll]);
                }
                return;
            }

            throw $e;
        }
    }

    public function upgrade(Database $db, SqlDialect $d, string $from): void {
        // místo pro řízené upgrade kroky
    }

    /** Nenabízí DROP TABLE, pouze kontrakt (view). */
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
        $this->stLog('BEGIN', [
        'module'=>static::class, 'table'=>$table, 'view'=>$view,
        'dialect'=>$d->value, 'isMysql'=>$d->isMysql()?1:0
        ]);
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
        $this->stLog('PRESENCE', [
        'table'   => $table,
        'hasTable'=> $hasTable ? 1 : 0,
        'view'    => $view,
        'hasView' => $hasView ? 1 : 0
        ]);

        // quick check indexů/FK – generátor doplní názvy
        $indexes = [[INDEX_NAMES_ARRAY]];
        $fks     = [[FK_NAMES_ARRAY]];
        $missingIdx = [];
        $missingFk  = [];

        if ($d->isMysql()) {
        // --- dump všech indexů v DB pro danou tabulku (pro srovnání podle jména) ---
        $dbIdx = $db->fetchAll(
            "SELECT DISTINCT INDEX_NAME AS idx
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t
            ORDER BY INDEX_NAME",
            [':t' => $table]
        ) ?? [];
        $this->stLog('IDX.DB', ['table'=>$table, 'have'=>array_map(fn($r)=>$r['idx'], $dbIdx)]);

            foreach ($indexes as $ix) {
                if ($ix === '') continue;
                $this->stLog('IDX.CMP', ['table'=>$table, 'expect'=>$ix]);
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.STATISTICS
                     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND INDEX_NAME = :i",
                    [':t'=>$table, ':i'=>$ix]
                );
                if ($cnt === 0) {
                    $this->stLog('IDX.MISS', ['table'=>$table, 'expect'=>$ix]);
                    $missingIdx[] = $ix;
                } else {
                    $this->stLog('IDX.HIT', ['table'=>$table, 'expect'=>$ix]);
                }
            }
            // --- dump všech FK názvů na tabulce (aby bylo jasné, co DB skutečně má) ---
            $dbFk = $db->fetchAll(
                "SELECT tc.CONSTRAINT_NAME AS cn
                FROM information_schema.TABLE_CONSTRAINTS tc
                WHERE tc.CONSTRAINT_SCHEMA = DATABASE()
                    AND tc.TABLE_NAME = :t
                    AND tc.CONSTRAINT_TYPE='FOREIGN KEY'
                ORDER BY tc.CONSTRAINT_NAME",
                [':t'=>$table]
            ) ?? [];
            $this->stLog('FK.DB', ['table'=>$table, 'have'=>array_map(fn($r)=>$r['cn'], $dbFk)]);

            foreach ($fks as $fk) {
                if ($fk === '') continue;
                $this->stLog('FK.CMP', ['table'=>$table, 'expect'=>$fk]);
                $cnt = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.REFERENTIAL_CONSTRAINTS
                     WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME = :c",
                    [':c'=>$fk]
                );
                if ($cnt === 0) {
                    $this->stLog('FK.MISS', ['table'=>$table, 'expect'=>$fk]);
                    $missingFk[] = $fk;
                } else {
                    $this->stLog('FK.HIT', ['table'=>$table, 'expect'=>$fk]);
                }
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
        $this->stLog('END', [
        'missing_idx' => $missingIdx,
        'missing_fk'  => $missingFk
        ]);
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
