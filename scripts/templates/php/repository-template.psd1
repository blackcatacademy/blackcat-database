@{
  File = 'src/Repository/[[ENTITY_CLASS]]Repository.php'
  Tokens = @(
    'NAMESPACE','ENTITY_CLASS','UPSERT_KEYS_ARRAY','UPSERT_UPDATE_COLUMNS_ARRAY','DATABASE_FQN'
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Repository;

use [[DATABASE_FQN]];
use [[NAMESPACE]]\Definitions;
use [[NAMESPACE]]\Criteria;
use BlackCat\Database\Contracts\ContractRepository as RepoContract;
use BlackCat\Database\Support\OrderByTools;

final class [[ENTITY_CLASS]]Repository implements RepoContract {
    use OrderByTools;
    public function __construct(private Database $db) {}

    /** Whitelist validních sloupců proti mass-assignmentu */
    private function filterCols(array $row): array {
        $out = [];
        foreach ($row as $k=>$v) {
            if (Definitions::hasColumn($k)) { $out[$k] = $v; }
        }
        return $out;
    }

    private function qi(string $ident): string
    {
        $parts = explode('.', $ident);
        if ($this->db->isMysql()) {
            return implode('.', array_map(fn($p) => "`$p`", $parts));
        }
        return implode('.', array_map(fn($p) => '"' . $p . '"', $parts));
    }

    /** Quote single identifier; pokud omylem přijde 't.col', deleguje na qi(). */
    private function q(string $id): string
    {
        if (str_contains($id, '.')) {
            // bezpečný fallback – nechá quoted i alias + sloupec
            return $this->qi($id);
        }
        return $this->db->isMysql() ? "`$id`" : '"' . $id . '"';
    }

    private function softGuard(string $alias = 't'): string {
        $soft = Definitions::softDeleteColumn();
        if (!$soft) return '1=1';
        $id = $alias !== '' ? "{$alias}.{$soft}" : $soft;
        return $this->qi($id) . ' IS NULL';
    }

    /** Zjistí zda 'version' sloupec je číselný (bez závislosti na test-harnessu). */
    private function isNumericVersion(): bool {
        return Definitions::versionIsNumeric();
    }

    private function normalizeInputRow(array $row): array {
        $aliases = Definitions::paramAliases();
        if (!$aliases) return $row;
        foreach ($aliases as $alias => $col) {
            if (array_key_exists($alias, $row) && !array_key_exists($col, $row)) {
                $row[$col] = $row[$alias];
            }
            unset($row[$alias]); // aliasy pryč, ať k PDO nejdou
        }
        return $row;
    }

    // ============ PK HELPERS (podpora složených PK) ============
    /** @return string[] */
    private function pkColumns(): array {
        if (method_exists(Definitions::class, 'pkColumns')) {
            $cols = Definitions::pkColumns();
            return array_values(array_map('strval', $cols));
        }
        return [Definitions::pk()];
    }

    /**
     * Převede $id na asociativní mapu ['col' => value] pro jednoduché i složené PK.
     * - scalar pro 1-sloupcový PK
     * - poziční pole [val1, val2] podle pořadí sloupců PK
     * - asociativní pole ['col1'=>v1,'col2'=>v2]
     * @param int|string|array $id
     * @return array<string, mixed>
     */
    private function normalizePkInput(int|string|array $id): array {
        $cols = $this->pkColumns();
        if (!is_array($id)) {
           if (count($cols) !== 1) {
                throw new \InvalidArgumentException('Composite PK vyžaduje pole hodnot (poziční nebo asociativní).');
            }
            return [ $cols[0] => $id ];
        }
        // asociativní vs poziční
        $isAssoc = array_keys($id) !== range(0, count($id) - 1);
        if ($isAssoc) {
            $out = [];
            foreach ($cols as $c) {
                if (!array_key_exists($c, $id)) {
                    throw new \InvalidArgumentException("Chybí hodnota pro PK sloupec '{$c}'.");
                }
                $out[$c] = $id[$c];
            }
            return $out;
        }
        if (count($id) !== count($cols)) {
            throw new \InvalidArgumentException('Počet hodnot v pozičním poli neodpovídá počtu PK sloupců.');
        }
        $out = [];
        foreach ($cols as $i => $c) { $out[$c] = $id[$i]; }
        return $out;
    }

    /**
     * Sestaví WHERE výraz pro PK a plní $params (placeholdery :pk_<col>).
     * @param string $alias tabulkový alias nebo ''.
     * @param array<string,mixed> $idMap
     */
    private function buildPkWhere(string $alias, array $idMap, array &$params, string $phPrefix = 'pk_'): string {
        $parts = [];
        foreach ($idMap as $col => $val) {
            $colId = $alias !== '' ? "{$alias}.{$col}" : $col;
            $parts[] = $this->qi($colId) . ' = :' . $phPrefix . $col;
            $params[$phPrefix . $col] = $val;
        }
        return implode(' AND ', $parts);
    }

    // ============ INSERT / BULK / UPSERT ============

    public function insert(array $row): void {
        $row = $this->normalizeInputRow($row);
        $row = $this->filterCols($row);
        if (!$row) { return; }

        $cols   = array_keys($row);
        sort($cols);
        $place  = array_map(fn($c)=>":".$c, $cols);

        // --- escapování identifikátorů
        $colsEsc = implode(',', array_map(fn($c) => $this->q($c), $cols));

        // Tabulku quotuj přes qi() (bezpečné i pro schema.table)
        $tbl     = Definitions::table();
        $tblEsc  = $this->qi($tbl);

        $sql   = "INSERT INTO {$tblEsc} ($colsEsc) VALUES (".implode(',', $place).")";

        // do params posíláme klíče BEZ dvojtečky
        $params = [];
        foreach ($cols as $c) { $params[$c] = $row[$c]; }

        $this->db->execute($sql, $params);
    }

    public function insertMany(array $rows): void {
        // 1) normalizace + whitelist + drop prázdných řádků
        $rows = array_values(array_filter(
            array_map(fn($r) => $this->filterCols($this->normalizeInputRow($r)), $rows),
            fn($r) => !empty($r)
        ));
        if (!$rows) return;

        // 2) sjednocení sloupců napříč všemi řádky
        $colSet = [];
        foreach ($rows as $r) {
            foreach ($r as $k => $_) { $colSet[$k] = true; }
        }
        $cols = array_keys($colSet);

        // --- escapování identifikátorů + deterministické pořadí sloupců
        sort($cols);
        $tbl     = Definitions::table();
        $tblEsc  = $this->qi($tbl);
        $colsEsc = implode(',', array_map(fn($c) => $this->q($c), $cols));

        // 3) postav placeholdery + parametry (missing -> NULL)
        $allPlace = [];
        $params = [];
        $i=0;
        foreach ($rows as $r) {
            $place = [];
            foreach ($cols as $c) {
                $ph  = ':p_'.$i.'_'.$c;   // placeholder se „:“ patří do SQL
                $key =  'p_'.$i.'_'.$c;   // klíč v $params bez „:“
                $place[]      = $ph;
                $params[$key] = $r[$c] ?? null;
            }
            $allPlace[] = '('.implode(',', $place).')';
            $i++;
        }

        $sql = "INSERT INTO {$tblEsc} ($colsEsc) VALUES ".implode(',', $allPlace);
        $this->db->execute($sql, $params);
    }

    /**
     * Dialekt-safe UPSERT (MySQL ON DUPLICATE KEY / Postgres ON CONFLICT).
     * [[UPSERT_KEYS_ARRAY]] = unikátní klíče (sloupce) pro konflikty,
     * [[UPSERT_UPDATE_COLUMNS_ARRAY]] = které sloupce aktualizovat.
     */
    public function upsert(array $row): void {
        $row = $this->normalizeInputRow($row);
        $row = $this->filterCols($row);
        if (!$row) return;

        $keys = [[UPSERT_KEYS_ARRAY]];
        $upd  = [[UPSERT_UPDATE_COLUMNS_ARRAY]];

        if (!$keys) {
            $uqs = Definitions::uniqueKeys();
            if (is_array($uqs) && isset($uqs[0]) && is_array($uqs[0]) && count($uqs[0]) > 0) {
                $keys = $uqs[0];
            } else {
                $keys = $this->pkColumns(); // fallback na PK (včetně composite)
            }
        }

        // --- připrav sloupce/parametry
        $cols  = array_keys($row);
        sort($cols);
        $place = array_map(fn($c)=>":".$c, $cols);

        $params = [];
        foreach ($cols as $c) { $params[$c] = $row[$c]; }

        $isMysql = $this->db->isMysql();
        $tbl     = Definitions::table();
        $tblEsc  = $this->qi($tbl);

        $colsEscIns = implode(',', array_map(fn($c) => $this->q($c), $cols));
        $colsEscKeys= implode(',', array_map(fn($c) => $this->q($c), $keys));

        // --- nikdy neupdatuj PK/konfliktní sloupce v DO UPDATE
        $pkCols = $this->pkColumns();
        $upd = array_values(array_diff($upd, array_merge($pkCols, $keys)));

        // --- sestav UPDATE seznamy
        $colSet   = array_fill_keys($cols, true);
        $mysqlUpd = [];
        $pgUpd    = [];

        foreach ($upd as $c) {
            if (!Definitions::hasColumn($c)) { continue; }
            if ($isMysql) {
                if (isset($colSet[$c])) { $mysqlUpd[] = $this->q($c) . ' = VALUES(' . $this->q($c) . ')'; }
            } else {
                if (isset($colSet[$c])) { $pgUpd[] = $this->q($c) . ' = EXCLUDED.' . $this->q($c); }
            }
        }

        // updated_at automaticky (pokud existuje a není už v seznamu)
        $updAt = Definitions::updatedAtColumn();
        if ($updAt) {
            if ($isMysql) {
                if (!in_array($updAt, $upd, true)) { $mysqlUpd[] = $this->q($updAt) . ' = CURRENT_TIMESTAMP'; }
            } else {
                if (!in_array($updAt, $upd, true)) { $pgUpd[] = $this->q($updAt) . ' = CURRENT_TIMESTAMP'; }
            }
        }

        if ($isMysql) {
            // MySQL vyžaduje nějaký UPDATE výraz – když není co updatovat, udělej no-op přes PK
            if (!$mysqlUpd) {
                $firstPk = $pkCols[0] ?? Definitions::pk();
                $mysqlUpd[] = $this->q($firstPk) . ' = ' . $this->q($firstPk);
            }
            $sql = "INSERT INTO {$tblEsc} ($colsEscIns) VALUES (".implode(',', $place).")"
                . " ON DUPLICATE KEY UPDATE " . implode(',', $mysqlUpd);
        } else {
            // Postgres: když není co updatovat → DO NOTHING (žádné '\"id\" = \"id\"' – to dělá ambiguitu)
            if ($pgUpd) {
                $sql = "INSERT INTO {$tblEsc} ($colsEscIns) VALUES (".implode(',', $place).")"
                    . " ON CONFLICT ($colsEscKeys) DO UPDATE SET " . implode(',', $pgUpd);
            } else {
                $sql = "INSERT INTO {$tblEsc} ($colsEscIns) VALUES (".implode(',', $place).")"
                    . " ON CONFLICT ($colsEscKeys) DO NOTHING";
            }
        }

        $this->db->execute($sql, $params);
    }

    // ============ UPDATE / DELETE / RESTORE ============

    public function updateById(int|string|array $id, array $row): int {
        // 0) aliasy → normalizace
        $row = $this->normalizeInputRow($row);

        $tbl     = Definitions::table();
        $tblEsc  = $this->qi($tbl);

        $pkCols = $this->pkColumns();
        $pkSet  = array_fill_keys($pkCols, true);
        $verCol = Definitions::versionColumn();
        $updAt  = Definitions::updatedAtColumn();

        // 1) expected version vytáhnout PŘED filtrem
        $hasExpectedVersion = false;
        $expectedVersion    = null;
        if ($verCol && array_key_exists($verCol, $row)) {
            $expectedVersion = is_numeric($row[$verCol]) ? (int)$row[$verCol] : $row[$verCol];
            unset($row[$verCol]);
            $hasExpectedVersion = true;
        }

        // 2) whitelisting vstupních sloupců
        $row = $this->filterCols($row);

        $params = [];
        $idMap  = $this->normalizePkInput($id);
        $wherePk = $this->buildPkWhere('', $idMap, $params, 'pk_');
        $assign = [];

        // ===== Optimistic locking přes WHERE =====
        if ($verCol && $hasExpectedVersion) {
            $verEsc = $this->q($verCol);

            // payload sloupce
            foreach ($row as $k => $v) {
                if (isset($pkSet[$k])) continue;
                $assign[]   = $this->q($k) . ' = :' . $k;
                $params[$k] = $v;
            }

            // vždy bump verze
            if ($this->isNumericVersion()) {
                $assign[] = $verEsc . ' = ' . $verEsc . ' + 1';
            }

            // updated_at pokud není v payloadu
            if ($updAt && !array_key_exists($updAt, $row)) {
                $assign[] = $this->q($updAt) . ' = CURRENT_TIMESTAMP';
            }

            if (empty($assign)) return 0;
            $params['expected_version'] = $expectedVersion;

            $sql = 'UPDATE ' . $tblEsc
                . ' SET ' . implode(', ', $assign)
                . ' WHERE ' . $wherePk . ' AND ' . $verEsc . ' = :expected_version';

            return $this->db->execute($sql, $params);
        }

        // ===== Klasický update bez optimistic verze =====
        foreach ($row as $k => $v) {
            if (isset($pkSet[$k])) continue;
            $assign[]   = $this->q($k) . " = :$k";
            $params[$k] = $v;
        }
        $hasPayloadChange = !empty($assign);

        if ($verCol && $hasPayloadChange && $this->isNumericVersion()) {
            $assign[] = $this->q($verCol) . ' = ' . $this->q($verCol) . ' + 1';
        }
        if ($updAt && !array_key_exists($updAt, $row)) {
            $assign[] = $this->q($updAt) . " = CURRENT_TIMESTAMP";
        }
        if (empty($assign)) return 0;

        $sql = "UPDATE {$tblEsc} SET " . implode(', ', $assign) . " WHERE {$wherePk}";
        return $this->db->execute($sql, $params);
    }

    public function deleteById(int|string|array $id): int {

        $tbl     = Definitions::table();
        $tblEsc  = $this->qi($tbl);
        $params  = [];
        $wherePk = $this->buildPkWhere('', $this->normalizePkInput($id), $params, 'pk_');

        $soft = Definitions::softDeleteColumn();
        if ($soft) {
            $updAt  = Definitions::updatedAtColumn();

            $setParts = [ $this->q($soft) . ' = CURRENT_TIMESTAMP' ];
            if ($updAt && $updAt !== $soft) {
                $setParts[] = $this->q($updAt) . ' = CURRENT_TIMESTAMP';
            }
            $set = implode(', ', $setParts);

            return $this->db->execute("UPDATE {$tblEsc} SET {$set} WHERE {$wherePk}", $params);
        }

        return $this->db->execute("DELETE FROM {$tblEsc} WHERE {$wherePk}", $params);
    }

    public function restoreById(int|string|array $id): int {

        $tbl     = Definitions::table();
        $tblEsc  = $this->qi($tbl);
        $params  = [];
        $wherePk = $this->buildPkWhere('', $this->normalizePkInput($id), $params, 'pk_');

        $soft = Definitions::softDeleteColumn();
        if (!$soft) return 0;

        $updAt = Definitions::updatedAtColumn();

        $setParts = [ $this->q($soft) . ' = NULL' ];
        if ($updAt && $updAt !== $soft) {
            $setParts[] = $this->q($updAt) . ' = CURRENT_TIMESTAMP';
        }
        $set = implode(', ', $setParts);

        return $this->db->execute("UPDATE {$tblEsc} SET $set WHERE {$wherePk}", $params);
    }

    // ============ READ / PAGE / LOCK ============

    public function findById(int|string|array $id): ?array {
        $view = Definitions::contractView();
        $tbl  = Definitions::table();
        $viewEsc = $this->qi($view);
        $tblEsc  = $this->qi($tbl);
        
        $params = [];
        $idMap  = $this->normalizePkInput($id);

        // 1) view (s aliasem t)
        $guardV = $this->softGuard('t');
        try {
            $whereV = $this->buildPkWhere('t', $idMap, $params, 'pk_');
            $sqlV = "SELECT t.* FROM {$viewEsc} t WHERE {$whereV} AND {$guardV}";
            $rowsV = $this->db->fetchAll($sqlV, $params);
            if ($rowsV) return $rowsV[0];
        } catch (\Throwable $e) { /* fallback níže */ }

        // 2) tabulka (bez aliasu)
        $guardT = $this->softGuard('');
        $whereT = $this->buildPkWhere('', $idMap, $params, 'pk_');
        $sqlT  = "SELECT * FROM {$tblEsc} WHERE {$whereT}";
        if ($guardT !== '1=1') { $sqlT .= " AND {$guardT}"; }
        $rowsT = $this->db->fetchAll($sqlT, $params);
        return $rowsT[0] ?? null;
    }

    public function exists(string $whereSql = '1=1', array $params = []): bool {
        $view = Definitions::contractView();
        $viewEsc = $this->qi($view);
        $where = '(' . $whereSql . ') AND ' . $this->softGuard();
        $sql = "SELECT 1 FROM {$viewEsc} t WHERE $where LIMIT 1";
        return (bool)$this->db->fetchOne($sql, $params);
    }

    public function count(string $whereSql = '1=1', array $params = []): int {
        $view = Definitions::contractView();
        $viewEsc = $this->qi($view);
        $where = '(' . $whereSql . ') AND ' . $this->softGuard();
        $sql = "SELECT COUNT(*) FROM {$viewEsc} t WHERE $where";
        return (int)$this->db->fetchOne($sql, $params);
    }

    /**
     * Stránkování přes Criteria (viz Criteria).
     * Vrací: ['items'=>[], 'total'=>int, 'page'=>int, 'perPage'=>int]
     */
    public function paginate(object $criteria): array
    {
        if (!$criteria instanceof Criteria) {
            throw new \InvalidArgumentException('Expected ' . Criteria::class);
        }
        /** @var Criteria $c */
        $c = $criteria;

        [$where, $params, $order, $limit, $offset, $joins] = $c->toSql(true);
        $where = '(' . $where . ') AND ' . $this->softGuard('t');
        $order = $order ?: (Definitions::defaultOrder() ?? (Definitions::pk().' DESC'));
        $orderSql = $this->buildOrderBy($order, Definitions::columns(), $this->db);

        $view  = Definitions::contractView();
        $viewEsc = $this->qi($view);
        $total = (int)$this->db->fetchOne("SELECT COUNT(*) FROM {$viewEsc} t $joins WHERE $where", $params);

        $sqlItems = "SELECT t.* FROM {$viewEsc} t $joins WHERE $where" . ($orderSql !== '' ? ' ' . $orderSql : '')
          . " LIMIT $limit OFFSET $offset";

        $items = $this->db->fetchAll($sqlItems, $params);
        return ['items'=>$items,'total'=>$total,'page'=>$c->page(),'perPage'=>$c->perPage()];
    }

    /** Přečtení a zamknutí řádku (tabulka, nikoli view) pro transakční práci */
    public function lockById(int|string|array $id): ?array {
        
        $tbl     = Definitions::table();
        $tblEsc  = $this->qi($tbl);
        $params = [];
        $wherePk = $this->buildPkWhere('', $this->normalizePkInput($id), $params, 'pk_');
        $rows = $this->db->fetchAll("SELECT * FROM {$tblEsc} WHERE {$wherePk} FOR UPDATE", $params);
        return $rows[0] ?? null;
    }
}
'@
}
