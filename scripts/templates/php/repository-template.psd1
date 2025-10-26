@{
  File = 'src/Repository/[[ENTITY_CLASS]]Repository.php'
  Tokens = @(
    'NAMESPACE','ENTITY_CLASS','TABLE','PK','UPSERT_KEYS_ARRAY','UPSERT_UPDATE_COLUMNS_ARRAY','PARAM_ALIASES_ARRAY','DATABASE_FQN'
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Repository;

use [[DATABASE_FQN]];
use [[NAMESPACE]]\Definitions;
use [[NAMESPACE]]\Criteria;
use BlackCat\Database\Contracts\ContractRepository as RepoContract;

final class [[ENTITY_CLASS]]Repository implements RepoContract {
    public function __construct(private Database $db) {}

    /** Whitelist validních sloupců proti mass-assignmentu */
    private function filterCols(array $row): array {
        $out = [];
        foreach ($row as $k=>$v) {
            if (Definitions::hasColumn($k)) { $out[$k] = $v; }
        }
        return $out;
    }

    private function softGuard(string $alias = 't'): string {
        $soft = Definitions::softDeleteColumn();
        if (!$soft) return '1=1';
        $prefix = ($alias !== '') ? ($alias . '.') : '';
        if ($this->db->isMysql()) {
            return "{$prefix}`$soft` IS NULL";
        }
        return $prefix . '"' . $soft . '" IS NULL';
    }

    /** @var array<string,string> alias => column */
    private const PARAM_ALIASES = [[PARAM_ALIASES_ARRAY]];

    private function normalizeInputRow(array $row): array {
        if (!self::PARAM_ALIASES) return $row;
        foreach (self::PARAM_ALIASES as $alias => $col) {
            if (array_key_exists($alias, $row) && !array_key_exists($col, $row)) {
                $row[$col] = $row[$alias];
            }
            unset($row[$alias]); // aliasy pryč, ať k PDO nejdou
        }
        return $row;
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
        $isMysql = $this->db->isMysql();
        $colsEsc = $isMysql
            ? implode(',', array_map(fn($c)=>"`$c`", $cols))
            : implode(',', array_map(fn($c)=>'"'.$c.'"', $cols));

        // Tabulku můžeš klidně quotovat také; je to bezpečné pro lowercase názvy.
        $tblEsc  = $isMysql ? '`[[TABLE]]`' : '"[[TABLE]]"';

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
        $isMysql = $this->db->isMysql();
        $quote   = fn($id) => $isMysql ? "`$id`" : '"'.$id.'"';
        $tblEsc  = $isMysql ? '`[[TABLE]]`' : '"[[TABLE]]"';
        $colsEsc = implode(',', array_map($quote, $cols));

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
            $keys = $uqs[0] ?? [Definitions::pk()];
        }

        $cols   = array_keys($row);
        sort($cols);
        $place  = array_map(fn($c)=>":".$c, $cols);

        $params = [];
        foreach ($cols as $c) {
            $params[$c] = $row[$c];
        }

        // ---- připrav update seznamy
        $mysqlUpd = [];
        $pgUpd    = [];
        $colSet   = array_fill_keys($cols, true);

        foreach ($upd as $c) {
            if (!Definitions::hasColumn($c)) { continue; }
            if ($this->db->isMysql()) {
                // aktualizuj jen to, co je v INSERT části
                if (isset($colSet[$c])) { $mysqlUpd[] = "`$c` = VALUES(`$c`)"; }
            } else {
                $pgUpd[] = "\"$c\" = EXCLUDED.\"$c\"";
            }
        }
        if ($this->db->isMysql() && !$mysqlUpd) {
            $pk = Definitions::pk(); $mysqlUpd[] = "`$pk` = `$pk`";
        }
        if (!$this->db->isMysql() && !$pgUpd) {
            $pk = Definitions::pk(); $pgUpd[] = "\"$pk\" = \"$pk\"";
        }

        $updAt = Definitions::updatedAtColumn();
        if ($updAt) {
            if ($this->db->isMysql()) {
                // přidej jen pokud už není v seznamu
                if (!in_array($updAt, $upd, true)) { $mysqlUpd[] = "`$updAt` = CURRENT_TIMESTAMP"; }
            } else {
                if (!in_array($updAt, $upd, true)) { $pgUpd[] = "\"$updAt\" = CURRENT_TIMESTAMP"; }
            }
        }

        $isMysql   = $this->db->isMysql();
        $quote     = fn($id) => $isMysql ? "`$id`" : '"'.$id.'"';
        $tblEsc    = $isMysql ? '`[[TABLE]]`' : '"[[TABLE]]"';
        $colsEscIns = implode(',', array_map($quote, $cols));

        if ($isMysql) {
            $sql = "INSERT INTO {$tblEsc} ($colsEscIns) VALUES (".implode(',', $place).")"
                . " ON DUPLICATE KEY UPDATE " . implode(',', $mysqlUpd);
        } else {
            $colsEscKeys = implode(',', array_map($quote, $keys));
            $sql = "INSERT INTO {$tblEsc} ($colsEscIns) VALUES (".implode(',', $place).")"
                . " ON CONFLICT ($colsEscKeys) DO UPDATE SET " . implode(',', $pgUpd);
        }

        $this->db->execute($sql, $params);
    }

    // ============ UPDATE / DELETE / RESTORE ============

    public function updateById(int|string $id, array $row): int {
        // 0) aliasy → normalizace
        $row = $this->normalizeInputRow($row);

        $isMysql = $this->db->isMysql();
        $quote   = fn($id) => $isMysql ? "`$id`" : '"'.$id.'"';
        $tblEsc  = $isMysql ? '`[[TABLE]]`' : '"[[TABLE]]"';

        $pk     = Definitions::pk();
        $pkEsc  = $quote($pk);
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

        $params = ['id' => $id];
        $assign = [];

        // ===== Optimistic locking přes WHERE =====
        if ($verCol && $hasExpectedVersion) {
            $verEsc = $quote($verCol);

            // payload sloupce
            foreach ($row as $k => $v) {
                if ($k === $pk) continue;
                $assign[]   = $quote($k) . ' = :' . $k;
                $params[$k] = $v;
            }

            // vždy bump verze
            $assign[] = $verEsc . ' = ' . $verEsc . ' + 1';

            // updated_at pokud není v payloadu
            if ($updAt && !array_key_exists($updAt, $row)) {
                $assign[] = $quote($updAt) . ' = CURRENT_TIMESTAMP';
            }

            if (empty($assign)) return 0;
            $params['expected_version'] = $expectedVersion;

            $sql = 'UPDATE ' . $tblEsc
                . ' SET ' . implode(', ', $assign)
                . ' WHERE ' . $pkEsc . ' = :id AND ' . $verEsc . ' = :expected_version';

            return $this->db->execute($sql, $params);
        }

        // ===== Klasický update bez optimistic verze =====
        foreach ($row as $k => $v) {
            if ($k === $pk) continue;
            $assign[]   = $quote($k) . " = :$k";
            $params[$k] = $v;
        }
        $hasPayloadChange = !empty($assign);

        if ($verCol && $hasPayloadChange) {
            $assign[] = $quote($verCol) . ' = ' . $quote($verCol) . ' + 1';
        }
        if ($updAt && !array_key_exists($updAt, $row)) {
            $assign[] = $quote($updAt) . " = CURRENT_TIMESTAMP";
        }
        if (empty($assign)) return 0;

        $sql = "UPDATE {$tblEsc} SET " . implode(', ', $assign) . " WHERE {$pkEsc} = :id";
        return $this->db->execute($sql, $params);
    }

    public function deleteById(int|string $id): int {
        $isMysql = $this->db->isMysql();
        $quote   = fn($id) => $isMysql ? "`$id`" : '"'.$id.'"';
        $tblEsc  = $isMysql ? '`[[TABLE]]`' : '"[[TABLE]]"';
        $pkEsc   = $quote(Definitions::pk());

        $soft = Definitions::softDeleteColumn();
        if ($soft) {
            $params = ['id'=>$id];
            $updAt  = Definitions::updatedAtColumn();

            $setParts = [ $quote($soft) . ' = CURRENT_TIMESTAMP' ];
            if ($updAt && $updAt !== $soft) {
                $setParts[] = $quote($updAt) . ' = CURRENT_TIMESTAMP';
            }
            $set = implode(', ', $setParts);

            return $this->db->execute("UPDATE {$tblEsc} SET {$set} WHERE {$pkEsc} = :id", $params);
        }

        return $this->db->execute("DELETE FROM {$tblEsc} WHERE {$pkEsc} = :id", ['id'=>$id]);
    }

    public function restoreById(int|string $id): int {
        $isMysql = $this->db->isMysql();
        $quote   = fn($id) => $isMysql ? "`$id`" : '"'.$id.'"';
        $tblEsc  = $isMysql ? '`[[TABLE]]`' : '"[[TABLE]]"';
        $pkEsc   = $quote(Definitions::pk());

        $soft = Definitions::softDeleteColumn();
        if (!$soft) return 0;

        $updAt = Definitions::updatedAtColumn();

        $setParts = [ $quote($soft) . ' = NULL' ];
        if ($updAt && $updAt !== $soft) {
            $setParts[] = $quote($updAt) . ' = CURRENT_TIMESTAMP';
        }
        $set = implode(', ', $setParts);

        return $this->db->execute("UPDATE {$tblEsc} SET $set WHERE {$pkEsc} = :id", ['id'=>$id]);
    }

    // ============ READ / PAGE / LOCK ============

    public function findById(int|string $id): ?array {
        $pk   = Definitions::pk();
        $view = Definitions::contractView();
        $tbl  = Definitions::table();
        $isMysql = $this->db->isMysql();
        $quote   = fn($id) => $isMysql ? "`$id`" : '"'.$id.'"';
        $pkEsc   = $quote($pk);

        $params = ['id' => $id];

        // 1) view (s aliasem t)
        $guardV = $this->softGuard('t');
        try {
            $sqlV  = "SELECT t.* FROM {$view} t WHERE t.{$pkEsc} = :id AND {$guardV}";
            $rowsV = $this->db->fetchAll($sqlV, $params);
            if ($rowsV) return $rowsV[0];
        } catch (\Throwable $e) { /* fallback níže */ }

        // 2) tabulka (bez aliasu)
        $guardT = $this->softGuard('');
        $sqlT  = "SELECT * FROM {$tbl} WHERE {$pkEsc} = :id";
        if ($guardT !== '1=1') { $sqlT .= " AND {$guardT}"; }
        $rowsT = $this->db->fetchAll($sqlT, $params);
        return $rowsT[0] ?? null;
    }

    public function exists(string $whereSql = '1=1', array $params = []): bool {
        $view = Definitions::contractView();
        $where = '(' . $whereSql . ') AND ' . $this->softGuard();
        $sql = "SELECT 1 FROM $view t WHERE $where LIMIT 1";
        return (bool)$this->db->fetchOne($sql, $params);
    }

    public function count(string $whereSql = '1=1', array $params = []): int {
        $view = Definitions::contractView();
        $where = '(' . $whereSql . ') AND ' . $this->softGuard();
        $sql = "SELECT COUNT(*) FROM $view t WHERE $where";
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
        $order = $order ?: (Definitions::defaultOrder() ?? '[[PK]] DESC');
        $joins = $joins ?: '';

        $view  = Definitions::contractView();
        $total = (int)$this->db->fetchOne("SELECT COUNT(*) FROM $view t $joins WHERE $where", $params);
        $items = $this->db->fetchAll("SELECT t.* FROM $view t $joins WHERE $where ORDER BY $order LIMIT $limit OFFSET $offset", $params);

        return ['items'=>$items,'total'=>$total,'page'=>$c->page(),'perPage'=>$c->perPage()];
    }

    /** Přečtení a zamknutí řádku (tabulka, nikoli view) pro transakční práci */
    public function lockById(int|string $id): ?array {
        $isMysql = $this->db->isMysql();
        $quote   = fn($id) => $isMysql ? "`$id`" : '"'.$id.'"';
        $tblEsc  = $isMysql ? '`[[TABLE]]`' : '"[[TABLE]]"';
        $pkEsc   = $quote(Definitions::pk());

        $rows = $this->db->fetchAll("SELECT * FROM {$tblEsc} WHERE {$pkEsc} = :id FOR UPDATE", ['id'=>$id]);
        return $rows[0] ?? null;
    }
}
'@
}
