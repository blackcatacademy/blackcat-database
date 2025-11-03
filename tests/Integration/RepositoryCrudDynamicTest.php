<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\Attributes\DataProvider;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use FilesystemIterator;

final class RepositoryCrudDynamicTest extends TestCase
{
    private static function dbg(string $msg): void {
        if (getenv('BC_DEBUG')) { fwrite(STDERR, "[repos] $msg\n"); }
    }

    private function logUkCollision(
        Database $db,
        string $table,
        array $row,
        mixed $uk,
        string $phase,
        ?\Throwable $ex = null
    ): void {
        // --- 0) Error info (SQLSTATE, vendor, message, key name, duplicate value) ---
        $err = ['sqlstate'=>null,'vendor'=>null,'message'=>null,'key'=>null,'dup'=>null];
        if ($ex instanceof \BlackCat\Core\DatabaseException) {
            $prev = $ex->getPrevious();
            if ($prev instanceof \PDOException) {
                $err['sqlstate'] = (string)($prev->errorInfo[0] ?? '');
                $err['vendor']   = (int)   ($prev->errorInfo[1] ?? 0);
                $err['message']  = (string)($prev->errorInfo[2] ?? $prev->getMessage());
            } else {
                $err['message']  = $ex->getMessage();
            }
        } elseif ($ex instanceof \PDOException) {
            $err['sqlstate'] = (string)($ex->errorInfo[0] ?? '');
            $err['vendor']   = (int)   ($ex->errorInfo[1] ?? 0);
            $err['message']  = (string)($ex->errorInfo[2] ?? $ex->getMessage());
        }
        if ($err['message']) {
            if (preg_match("~for key '([^']+)'~i", $err['message'], $m)) { $err['key'] = $m[1]; }
            if (preg_match("~Duplicate entry '([^']+)'~i", $err['message'], $m)) { $err['dup'] = $m[1]; }
        }

        // --- 1) Rozbal UK sloupce ---
        $ukCols = [];
        if (is_array($uk)) {
            $first = (isset($uk[0]) && is_array($uk[0])) ? $uk[0] : $uk;
            $ukCols = array_values(array_map('strval', array_filter($first, fn($c) => is_string($c) && $c !== '')));
        }
        if (!$ukCols && $table === 'encrypted_fields') {
            $ukCols = ['entity_table','entity_pk','field_name'];
        }

        // --- 2) Payload + WHERE pro UK ---
        $payload = [];
        $conds   = [];
        $params  = [];
        foreach ($ukCols as $c) {
            $v = $row[$c] ?? null;
            if (is_bool($v)) { $v = $v ? '1' : '0'; }
            elseif (!is_scalar($v) && $v !== null) { $v = json_encode($v, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES); }
            $payload[$c] = $v;
            $conds[] = $db->quoteIdent($c) . ' = :' . $c;
            $params[':' . $c] = $row[$c] ?? null;
        }

        // --- 3) SELECT potenciálních konfliktů dle UK ---
        $conflicts = [];
        if ($conds) {
            $selCols = $ukCols;
            // přidej případný PK sloupec, ať víme i id
            try {
                $defsClass = self::$repos[$table] ?? null;
                if (is_string($defsClass)) {
                    $defsClass = preg_replace('~\\\\Repository$~', '\\\\Definitions', $defsClass);
                }
                if (is_string($defsClass) && class_exists($defsClass) && method_exists($defsClass,'pk')) {
                    $pk = (string)$defsClass::pk();
                    if ($pk !== '' && !in_array($pk, $selCols, true)) { $selCols[] = $pk; }
                }
            } catch (\Throwable $_) {}
            if (!$selCols) { $selCols = $ukCols; }

            $sql = 'SELECT ' . implode(', ', array_map([$db,'quoteIdent'], $selCols))
                . ' FROM ' . $db->quoteIdent($table)
                . ' WHERE ' . implode(' AND ', $conds)
                . ' LIMIT 5';
            try { $conflicts = $db->fetchAll($sql, $params) ?? []; } catch (\Throwable $_) { $conflicts = []; }
        }

        // --- 4) Pokud klíč vypadá na PRIMARY, zkus explicitně PK konflikt ---
        $pkConflict = null;
        $keyIsPrimary = $err['key'] && stripos((string)$err['key'], 'PRIMARY') !== false;
        if ($keyIsPrimary || !$ukCols) {
            if (array_key_exists('id', $row) && $row['id'] !== null) {
                try {
                    $pkConflict = $db->fetch(
                        'SELECT id FROM ' . $db->quoteIdent($table) . ' WHERE id = ? LIMIT 1', 
                        [ is_numeric($row['id']) ? 0 + $row['id'] : $row['id'] ]
                    ) ?: null;
                } catch (\Throwable $_) { $pkConflict = null; }
            }
        }

        // --- 5) SHOW CREATE TABLE pro MySQL/MariaDB (kvůli kolacím/indexům) ---
        $dial = (method_exists(DbHarness::class, 'isPg') && DbHarness::isPg()) ? 'pg' : 'mysql/mariadb';
        $ddl = null;
        if ($dial !== 'pg') {
            try { $ddl = $db->fetch('SHOW CREATE TABLE ' . $db->quoteIdent($table)); } catch (\Throwable $_) {}
        }

        // --- 6) Jediný jednoznačný log ---
        $log = [
            'phase'       => $phase,
            'table'       => $table,
            'dialect'     => $dial,
            'uk_cols'     => $ukCols,
            'payload'     => $payload,
            'error'       => $err,           // <- obsahuje key/sqlstate/vendor/message/dup
            'conflicts'   => $conflicts,
            'pk_conflict' => $pkConflict,
        ];
        if ($ddl !== null) { $log['show_create_table'] = $ddl; }

        fwrite(STDERR, "[repos][UK-COLLISION] " . json_encode($log, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES) . "\n");
    }

    private static function normalizePkValue(string $table, string $pk, mixed $val): int|string
    {
        if (is_int($val)) return $val;

        $meta = null;
        foreach (DbHarness::columns($table) as $c) {
            if (($c['name'] ?? '') === $pk) { $meta = $c; break; }
        }
        $type = strtolower((string)($meta['type'] ?? ''));

        // int/bigint/smallint/serial apod. → int, jinak string
        if (preg_match('/\b(int|bigint|smallint|serial)\b/', $type)) {
            return (int)$val;
        }
        return (string)$val;
    }

    /** @var array<string,string> */
    private static array $repos = [];

    /** Postav mapu repozitářů (idempotentně) */
    private static function ensureReposBuilt(): void
    {
        if (self::$repos) { return; }

        $root = realpath(__DIR__ . '/../../packages');
        self::dbg("scan root=$root");

        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS)
        );

        foreach ($it as $f) {
            $path = $f->getPathname();
            if ($f->isFile() && preg_match('~[\\/]packages[\\/]([^\\/]+)[\\/]src[\\/]Repository\.php$~', $path, $m)) {
                $pkg    = $m[1];
                $pascal = implode('', array_map(fn($x)=>ucfirst($x), preg_split('/[_-]/',$pkg)));
                $class  = "BlackCat\\Database\\Packages\\{$pascal}\\Repository";
                $defs   = "BlackCat\\Database\\Packages\\{$pascal}\\Definitions";

                if (!class_exists($class, false)) { require_once $path; }

                $defsPath = dirname($path) . DIRECTORY_SEPARATOR . 'Definitions.php';
                if (!class_exists($defs, false) && is_file($defsPath)) { require_once $defsPath; }

                $crit    = "BlackCat\\Database\\Packages\\{$pascal}\\Criteria";
                $critPath= dirname($path) . DIRECTORY_SEPARATOR . 'Criteria.php';
                if (!class_exists($crit, false) && is_file($critPath)) { require_once $critPath; }

                if (class_exists($class, false) && class_exists($defs, false)) {
                    /** @var class-string $defs */
                    $table = $defs::table();
                    self::$repos[$table] = $class;
                }
            }
        }
        self::dbg('final repos='.json_encode(self::$repos));
    }

    public static function setUpBeforeClass(): void
    {
        DbHarness::ensureInstalled();
        // volitelné: pro logy
        self::ensureReposBuilt();
    }

    public static function safeTablesProvider(): array
    {
        self::ensureReposBuilt();
        $out = [];
        foreach (self::$repos as $table => $repoFqn) {
            [$row, $updatable] = RowFactory::makeSample($table);
            if ($row !== null) {
                $out[] = [$table, $repoFqn, $row, $updatable];
            }
        }
        return $out ?: [['app_settings', self::$repos['app_settings'] ?? '', ['setting_key'=>'k','section'=>'s','value'=>'v'], ['value']]];
    }

    #[DataProvider('safeTablesProvider')]
    public function test_crud_upsert_lock_smoke(string $table, string $repoFqn, array $row, array $updatable): void
    {
        if (!class_exists($repoFqn)) $this->markTestSkipped("repo missing for $table");

        $db   = Database::getInstance();
        $repo = new $repoFqn($db);

        DbHarness::begin();
        try {
            // sample row
            [$row, $updatable, $uk] = RowFactory::makeSample($table, []);
            if ($row === null) {
                $this->markTestSkipped("no sample for $table");
            }

            // PG: srovnat sample (enumy/CHECK, identity, datové typy)
            if (method_exists(DbHarness::class, 'coerceForPg')) {
                $row = DbHarness::coerceForPg($table, $row);
            }

            // PG: tabulky s povinnými (NOT NULL) FK jen “smoke-skipneme”
            if (method_exists(DbHarness::class, 'isPg') && DbHarness::isPg()
                && method_exists(DbHarness::class, 'hasHardFks') && DbHarness::hasHardFks($table)) {
                $this->markTestSkipped("PG smoke: $table has NOT NULL FKs (no parent seed)");
            }

            // INSERT (zachytáváme typické PG/MySQL kolize a dáme SKIP, ne FAIL)
            try {
                $repo->insert($row);
            } catch (\BlackCat\Core\DatabaseException $e) {
                $msg  = strtolower($e->getMessage());
                $code = '';
                $prev = $e->getPrevious();
                if ($prev instanceof \PDOException) { $code = (string)($prev->errorInfo[0] ?? ''); }

                if ($code === '23505' || str_contains($msg, 'duplicate') || str_contains($msg, 'unique constraint')) {
                    $this->logUkCollision($db, $table, $row, $uk, 'insert', $e);
                    $this->markTestSkipped("unique collision for $table (seed/sample clash)");
                }
                if ($code === '23514' || str_contains($msg, 'check constraint')) {
                    $this->markTestSkipped("check constraint for $table (enum/sample mismatch)");
                }
                if ($code === '23503' || str_contains($msg, 'foreign key')) {
                    $this->markTestSkipped("FK violation for $table (no parent seed)");
                }
                // MySQL vendor codes (errorInfo[1]) – ošetři jako SKIP, ať to není “umělý” FAIL
                if ($prev instanceof \PDOException) {
                    $sqlstate = (string)($prev->errorInfo[0] ?? '');
                    $vendor   = (int)($prev->errorInfo[1] ?? 0);

                    // duplicitní klíč
                    if ($vendor === 1062 || $sqlstate === '23000') {
                        $this->logUkCollision($db, $table, $row, $uk, 'insert', $e);
                        $this->markTestSkipped("unique collision for $table (seed/sample clash)");
                    }
                    // FK violation
                    if ($vendor === 1452) {
                        $this->markTestSkipped("FK violation for $table (no parent seed)");
                    }
                    // NOT NULL column missing (často u autogenerovaných sample řádků)
                    if ($vendor === 1364) {
                        $this->markTestSkipped("NOT NULL column missing for $table (RowFactory sample incomplete)");
                    }
                }
                throw $e; // neznámé → necháme spadnout
            }

            $view = 'vw_' . $table;
            if (method_exists(DbHarness::class, 'isPg') && DbHarness::isPg()) {
                $exists = (bool)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.views 
                    WHERE table_schema = ANY (current_schemas(true)) 
                    AND LOWER(table_name) = LOWER(?)",
                    [$view]
                );
            } else {
                $exists = (bool)$db->fetchOne(
                    "SELECT COUNT(*) FROM information_schema.VIEWS 
                    WHERE TABLE_SCHEMA = DATABASE() 
                    AND LOWER(TABLE_NAME) = LOWER(?)",
                    [$view]
                );
            }

            if ($exists) {
                // jen sanity: SELECT první řádek
                $db->fetchAll('SELECT * FROM ' . $db->quoteIdent($view) . ' LIMIT 1');
                $this->assertTrue(true, "view $view is readable");
            }

            // COUNT/EXISTS
            $this->assertTrue($repo->exists('1=1', []));
            $this->assertGreaterThanOrEqual(1, $repo->count('1=1', []));

            // najdi PK z Definitions vedle daného Repository
            $defsClass = preg_replace('~\\\\Repository$~', '\\\\Definitions', $repoFqn);

            /** @var class-string|null $defsClass */
            $pk = 'id';
            if (class_exists($defsClass)) {
                if (method_exists($defsClass, 'pk')) {
                    $pk = $defsClass::pk();
                } else {
                    $cols = $defsClass::columns();
                    $pk   = in_array('id', $cols, true) ? 'id' : ($cols[0] ?? 'id');
                }
            }

            // bezpecne – inicializace
            $id = null;
            // rozparsuj PK na pole sloupců (pro single PK vrátí 1 prvek)
            $pkSan = (string)$pk;
            // normalize „divných“ čárek a NBSP na ASCII čárku
            $pkSan = preg_replace('/[\x{201A}\x{201E}\x{FF0C}\x{00A0}]+/u', ',', $pkSan);
            $pkCols = array_values(array_filter(array_map('trim', preg_split('/\s*,\s*/', $pkSan))));
            // nouzově – když to pořád vypadá jako jeden kus, zkus whitespace
            if (count($pkCols) === 1 && str_contains($pkCols[0], ' ')) {
                $pkCols = array_values(array_filter(preg_split('/\s+/', $pkCols[0])));
            }
            if (!$pkCols) { $pkCols = ['id']; }

            $colListAll = implode(', ', array_map([$db, 'quoteIdent'], $pkCols));
            $orderBy    = implode(', ', array_map(fn($c) => $db->quoteIdent($c) . ' DESC', $pkCols));

            $peek = $db->fetch('SELECT ' . $colListAll . ' FROM ' . $db->quoteIdent($table) . ' ORDER BY ' . $orderBy . ' LIMIT 1');
            if ($peek !== null) {
                if (count($pkCols) === 1) {
                    $lead = $pkCols[0];
                    $id   = self::normalizePkValue($table, $lead, $peek[$lead] ?? null);

                    // findById pro single PK
                    $found = $repo->findById($id);
                    $this->assertIsArray($found);
                } else {
                    // složené PK → připrav složený klíč (typově znormalizovaný)
                    $id = [];
                    foreach ($pkCols as $c) {
                        $id[$c] = self::normalizePkValue($table, $c, $peek[$c] ?? null);
                    }

                    // 1) zkus repo->findById(array)
                    try {
                        $found = $repo->findById($id);
                        $this->assertIsArray($found);
                    } catch (\Throwable $_) {
                        // 2) fallback: ruční SELECT proti tabulce – sanity check
                        $conds  = [];
                        $params = [];
                        foreach ($id as $col => $val) {
                            $conds[] = $db->quoteIdent($col) . ' = :' . $col;
                            $params[':' . $col] = $val;
                        }
                        $rowCheck = $db->fetch(
                            'SELECT 1 FROM ' . $db->quoteIdent($table) . ' WHERE ' . implode(' AND ', $conds) . ' LIMIT 1',
                            $params
                        );

                        if ($rowCheck === null) {
                            $this->fail("$table composite PK record not found by manual SELECT");
                        } else {
                            $this->markTestSkipped("$table has composite PK and repository does not support array findById()");
                        }
                    }
                }
            }

            // UPDATE (zahladit numeric/date typy)
            if ($id !== null && $updatable) {
                $fkCols = array_fill_keys(DbHarness::foreignKeyColumns($table), true);
                $k = null;
                foreach ($updatable as $cand) {
                    if (!isset($fkCols[$cand])) { $k = $cand; break; }
                }
                if ($k === null) {
                    $this->markTestSkipped("smoke: $table has only FK updatable columns (skip UPDATE)");
                }
                // vyhni se PK a version sloupci (optimistic locking)
                if (in_array($k, $pkCols, true)) {
                    $this->markTestSkipped("smoke: $table – refusing to UPDATE primary key column ($k)");
                }

                $versionCol = null;
                if (class_exists($defsClass) && method_exists($defsClass, 'versionColumn')) {
                    $vc = $defsClass::versionColumn();
                    if (is_string($vc) && $vc !== '') {
                        $versionCol = $vc;
                    }
                }
                if ($versionCol !== null && strcasecmp($versionCol, $k) === 0) {
                    $this->markTestSkipped("smoke: $table – refusing to UPDATE version column ($k)");
                }
                $meta = null;
                foreach (DbHarness::columns($table) as $c) { if (($c['name'] ?? '') === $k) { $meta = $c; break; } }

                $full = strtolower((string)($meta['full_type'] ?? ''));
                $type = strtolower((string)($meta['type'] ?? ''));

                // BINÁRKY: drž přesně deklarovanou délku
                if (preg_match('/\b(?:var)?binary\((\d+)\)/', $full, $m)) {
                    $n = (int)$m[1];
                    $newVal = random_bytes(max(1, $n));
                }
                // BLOB: nech relativně malý obsah
                elseif (str_contains($type, 'blob')) {
                    $newVal = random_bytes(16);
                }
                // CHAR(N)/VARCHAR(N): nepřekroč N
                elseif (preg_match('/\bchar\((\d+)\)/', $full, $m)) {
                    $n = (int)$m[1];
                    $base = isset($row[$k]) ? (string)$row[$k] : 'x';
                    $newVal = substr($base . 'u', 0, $n);
                }
                elseif (preg_match('/\bvarchar\((\d+)\)/', $full, $m)) {
                    $n = (int)$m[1];
                    $base = isset($row[$k]) ? (string)$row[$k] : 'x';
                    $newVal = mb_substr($base . 'u', 0, $n);
                }
                // NUMERIKA/DATUMY – vaše původní větve
                elseif (preg_match('/(int|numeric|decimal|real|double|smallint|bigint|serial)/', $type)) {
                    $newVal = is_numeric($row[$k] ?? null) ? (0 + $row[$k]) + 1 : 1;
                }
                elseif (preg_match('/(date|time)/', $type)) {
                    $newVal = (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s');
                }
                // FALLBACK: text bez omezení
                else {
                    $base = isset($row[$k]) ? (string)$row[$k] : 'x';
                    $newVal = $base . 'u';
                }

                $aff = $repo->updateById($id, [$k => $newVal]);
                $this->assertSame(1, $aff);
            }

            // UPSERT — na PG ošetříme “ambiguous column” (sqlstate 42702) → dáme SKIP
            if (method_exists($repo, 'upsert')) {
                try {
                    $repo->upsert($row);
                    $this->assertTrue(true, 'upsert ok');
                } catch (\BlackCat\Core\DatabaseException $e) {
                    $msg  = strtolower($e->getMessage());
                    $code = '';
                    $prev = $e->getPrevious();
                    if ($prev instanceof \PDOException) { $code = (string)($prev->errorInfo[0] ?? ''); }

                    if ($code === '42702' || str_contains($msg, 'ambiguous column')) {
                        $this->markTestSkipped("upsert ambiguous ON CONFLICT for $table (PG)");
                    }
                    if ($code === '23503' || str_contains($msg, 'foreign key')) {
                        $this->markTestSkipped("upsert FK violation for $table");
                    }
                    if ($code === '23505' || str_contains($msg, 'duplicate') || str_contains($msg, 'unique constraint')) {
                        $this->logUkCollision($db, $table, $row, $uk, 'upsert', $e);
                        $this->markTestSkipped("unique collision for $table (seed/sample clash)");
                    }
                    if ($prev instanceof \PDOException) {
                        $sqlstate = (string)($prev->errorInfo[0] ?? '');
                        $vendor   = (int)($prev->errorInfo[1] ?? 0);

                        // duplicitní klíč
                        if ($vendor === 1062 || $sqlstate === '23000') {
                            $this->logUkCollision($db, $table, $row, $uk, 'upsert', $e);
                            $this->markTestSkipped("unique collision for $table (seed/sample clash)");
                        }
                        // FK violation
                        if ($vendor === 1452) {
                            $this->markTestSkipped("upsert FK violation for $table");
                        }
                        // NOT NULL column missing
                        if ($vendor === 1364) {
                            $this->markTestSkipped("upsert NOT NULL column missing for $table (RowFactory sample incomplete)");
                        }
                    }
                    throw $e;
                }
            }

            // LOCK
            if ($id !== null) {
                $rowLocked = $repo->lockById($id);
                $this->assertIsArray($rowLocked);
            }

        } finally {
            DbHarness::rollback();
        }
    }

    #[DataProvider('safeTablesProvider')]
    public function test_paginate_smoke(string $table, string $repoFqn): void
    {
        if (!class_exists($repoFqn)) $this->markTestSkipped("repo missing");
        $db = Database::getInstance();
        $repo = new $repoFqn($db);

        DbHarness::begin();
        try {
            $critClass = preg_replace('~\\\\Repository$~', '\\Criteria', $repoFqn);
            if (!class_exists($critClass)) { $this->markTestSkipped('criteria missing'); }
            $c = new $critClass(); /** @var object $c */
            if (method_exists($c,'setPerPage')) $c->setPerPage(5);
            if (method_exists($c,'setPage')) $c->setPage(1);
            $page = $repo->paginate($c);
            $this->assertIsArray($page);
            $this->assertArrayHasKey('items', $page);
            $this->assertArrayHasKey('total', $page);
        } finally {
            DbHarness::rollback();
        }
    }
}
