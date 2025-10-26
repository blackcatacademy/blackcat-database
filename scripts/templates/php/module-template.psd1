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
        $table = $this->table();
        $view  = self::contractView();

        if ($d->isMysql()) {
            $db->exec("DROP VIEW IF EXISTS `{$view}`");
            $db->exec("CREATE VIEW `{$view}` AS SELECT * FROM `{$table}`");
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
            $table = $m[1]; // může už být v uvozovkách/backtickách
            $name  = $m[2];

            // odstripované názvy pro dotaz do information_schema
            $tabName = trim($table, '`"');
            $chkName = trim($name,  '`"');

            if ($db->isMysql()) {
                // MySQL NEMÁ "DROP CHECK IF EXISTS" → udělej předcheck
                $exists = (int)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                    WHERE CONSTRAINT_SCHEMA = DATABASE()
                    AND TABLE_NAME = :t
                    AND CONSTRAINT_NAME = :c
                    AND CONSTRAINT_TYPE = 'CHECK'",
                    [':t'=>$tabName, ':c'=>$chkName]
                ) > 0;

                if ($exists) {
                    // bez IF EXISTS
                    $db->exec("ALTER TABLE $table DROP CHECK $name");
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
            $prev = $e->getPrevious();
            $msg  = strtolower((string)$e->getMessage());
            $isMy = $db->isMysql();

            $sqlstate = ($prev instanceof \PDOException) ? (string)($prev->errorInfo[0] ?? '') : '';
            $code     = ($prev instanceof \PDOException) ? (int)($prev->errorInfo[1] ?? 0) : 0;

            $tolerate = false;
            if ($isMy) {
                $tolerate = in_array($code, [1050,1051,1060,1061,1091,1826,3822], true) // ← přidáno 3822
                            || str_contains($msg, 'already exists')
                            || str_contains($msg, 'duplicate')
                            || str_contains($msg, 'cannot drop index')
                            || str_contains($msg, 'cannot add foreign key constraint');
            } else {
                $tolerate = in_array($sqlstate, ['42P07','42710','42701'], true)
                            || str_contains($msg, 'already exists');
            }
            if ($tolerate) { return; }
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

        // quick check indexů/FK – generátor doplní názvy
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
