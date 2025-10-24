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

        // Najdi soubory ve tvaru 000_nazev.<dial>.sql NEBO 000_nazev_<dial>.sql
        $files = array_merge(
            glob($dir.'/*.'. $dial .'.sql') ?: [],
            glob($dir.'/*_' . $dial .'.sql') ?: []
        );
        // odstraň duplicity a seřaď podle číselného prefixu
        $files = array_values(array_unique($files));
        usort($files, static function($a, $b) {
            $pa = (int)preg_replace('~^.*?/([0-9]{3})_.*$~', '$1', $a);
            $pb = (int)preg_replace('~^.*?/([0-9]{3})_.*$~', '$1', $b);
            return $pa <=> $pb ?: strcmp($a, $b);
        });

        foreach ($files as $path) {
            $this->execSqlFileStreamed($db, $path);
        }
    }

    /** Provede SQL soubor po částech (streamovaně), aby se nealokoval celý obsah do paměti. */
    private function execSqlFileStreamed(Database $db, string $path): void {
        $fh = @fopen($path, 'rb');
        if ($fh === false) { return; }

        $buf = '';
        while (!feof($fh)) {
            $chunk = fread($fh, 65536);
            if ($chunk === false) { break; }
            $buf .= $chunk;

            while (true) {
                $posN  = strpos($buf, ";\n");
                $posRN = strpos($buf, ";\r\n");
                $pos = ($posN === false) ? $posRN : (($posRN === false) ? $posN : min($posN, $posRN));
                if ($pos === false) { break; }

                $stmt = trim(substr($buf, 0, $pos));
                $buf  = substr($buf, ($pos === $posRN) ? $pos + 3 : $pos + 2);
                if ($stmt !== '') { $this->safeExec($db, $stmt); }
            }
        }
        fclose($fh);

        $tail = trim($buf);
        if ($tail !== '') { $this->safeExec($db, $tail); }
    }

    /** Provede DDL, ale toleruje „already exists / duplicate / unknown“ situace pro idempotenci. */
    private function safeExec(Database $db, string $sql): void {
        try {
            $db->exec($sql);
        } catch (\BlackCat\Core\DatabaseException $e) {
            $prev = $e->getPrevious();
            $msg  = strtolower((string)$e->getMessage());
            $isMy = $db->isMysql();

            $sqlstate = ($prev instanceof \PDOException) ? (string)($prev->errorInfo[0] ?? '') : '';
            $code     = ($prev instanceof \PDOException) ? (int)($prev->errorInfo[1] ?? 0) : 0;

            $tolerate = false;
            if ($isMy) {
                // MySQL duplicitní/již existující objekt apod.
                // 1050 table exists, 1051 unknown table, 1060 dup column, 1061 dup index,
                // 1091 unknown key/column in drop, 1826 dup foreign key, 1832 cannot change column (při opakovaném add)
                $tolerate = in_array($code, [1050,1051,1060,1061,1091,1826], true)
                            || str_contains($msg, 'already exists')
                            || str_contains($msg, 'duplicate')
                            || str_contains($msg, 'cannot drop index')
                            || str_contains($msg, 'cannot add foreign key constraint and it already exists');
            } else {
                // Postgres duplicitní/již existující objekt
                // 42P07 duplicate_table, 42710 duplicate_object, 42701 duplicate_column
                $tolerate = in_array($sqlstate, ['42P07','42710','42701'], true)
                            || str_contains($msg, 'already exists');
            }

            // DROP IF EXISTS by problém řeší, ale když ho schema soubory nemají, tolerujme opakovaný běh
            if ($tolerate) { return; }
            throw $e;
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
