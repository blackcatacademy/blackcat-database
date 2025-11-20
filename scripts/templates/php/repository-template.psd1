@{
  File = 'src/Repository/[[ENTITY_CLASS]]Repository.php'
  Tokens = @(
   'NAMESPACE','ENTITY_CLASS','DTO_CLASS',
   'UPSERT_KEYS_ARRAY','UPSERT_UPDATE_COLUMNS_ARRAY','DATABASE_FQN','UNIQUE_HELPERS'
 )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Repository;

use [[DATABASE_FQN]] as Database;              // e.g. BlackCat\Core\Database
use [[NAMESPACE]]\Definitions;
use [[NAMESPACE]]\Criteria;
use [[NAMESPACE]]\Dto\[[DTO_CLASS]] as Dto;
use [[NAMESPACE]]\Mapper\[[DTO_CLASS]]Mapper as RowMapper;
use BlackCat\Database\Contracts\ContractRepository as RepoContract;
use BlackCat\Database\Contracts\KeysetRepository as KeysetRepoContract;
use BlackCat\Database\Support\OrderByTools;
use BlackCat\Database\Support\SqlIdentifier as Ident;
use BlackCat\Database\Support\PkTools;
use BlackCat\Database\Support\LockMode;
use BlackCat\Database\Support\KeysetPaginator;
use BlackCat\Database\Support\UpsertBuilder;
use BlackCat\Database\Support\RepositoryHelpers;

final class [[ENTITY_CLASS]]Repository implements RepoContract, KeysetRepoContract
{
    use OrderByTools, PkTools, RepositoryHelpers;

    public function __construct(private readonly Database $db) {}

    /**
     * Optionally override the Definitions FQN – trait otherwise infers it from the repository FQN.
     */
    protected function def(): string { return \[[NAMESPACE]]\Definitions::class; }

    /** @return array<string,mixed>|Dto|null */
    private function mapReturn(?array $row, bool $asDto): array|Dto|null {
        if (!$asDto || !$row) return $row;
        return RowMapper::fromRow($row);
    }

    /** @return array<string,mixed>|Dto|null */
    public function getById(int|string|array $id, bool $asDto = false): array|Dto|null {
        $row = $this->findById($id);
        return $this->mapReturn($row, $asDto);
    }

    // --- INSERT / BULK -------------------------------------------------------

    public function insert(array #[\SensitiveParameter] $row): void {
        $row = $this->filterCols($this->normalizeInputRow($row));
        if (!$row) return;

        $cols = array_keys($row); sort($cols);
        $tbl  = Ident::qi($this->db, Definitions::table());
        $colSql = implode(',', array_map(fn($c) => Ident::q($this->db, $c), $cols));
        $phSql  = implode(',', array_map(fn($c) => ':' . $c, $cols));

        $this->db->execute("INSERT INTO {$tbl} ({$colSql}) VALUES ({$phSql})", $row);
    }

    public function insertMany(array $rows): void {
        $rows = array_values(array_filter(
            array_map(fn($r) => $this->filterCols($this->normalizeInputRow($r)), $rows),
            fn($r) => !empty($r)
        ));
        if (!$rows) return;

        // unify columns across rows (missing entries -> NULL)
        $cols = array_keys(array_reduce($rows, fn($a,$r)=>$a + array_fill_keys(array_keys($r),true), []));
        sort($cols);

        $tbl    = Ident::qi($this->db, Definitions::table());
        $colSql = implode(',', array_map(fn($c)=>Ident::q($this->db,$c), $cols));

        // conservative upper bound on parameters per INSERT
        $maxParams = 32000;
        $perRow    = max(1, count($cols));
        $chunkSize = max(1, intdiv($maxParams, $perRow));

        for ($o = 0; $o < count($rows); $o += $chunkSize) {
            $slice  = array_slice($rows, $o, $chunkSize);
            $valuesSql = [];
            $params    = [];
            $i = 0;
            foreach ($slice as $r) {
                $ph=[]; foreach ($cols as $c) { $k="p_{$o}_{$i}_{$c}"; $ph[]=":{$k}"; $params[$k]=$r[$c]??null; }
                $valuesSql[]='('.implode(',', $ph).')'; $i++;
            }
            $this->db->execute("INSERT INTO {$tbl} ({$colSql}) VALUES ".implode(',', $valuesSql), $params);
        }
    }

    // --- UPSERT (including "revive" mode) ---------------------------------------

    /** Internal helper: apply the "revive" policy (soft-delete -> NULL) before buildRow(). */
    private function applyUpsertRevivePolicy(array $row, array $updateCols, bool $revive): array
    {
        if (!$revive) {
            return [$row, $updateCols];
        }
        $soft = Definitions::softDeleteColumn();
        if ($soft) {
            // CLEAR: deleted_at = NULL on conflict
            $row[$soft] = null;
            if (!in_array($soft, $updateCols, true)) {
                $updateCols[] = $soft;
            }
        }
        return [$row, $updateCols];
    }

    /** Standard upsert – preserves soft-delete (no revive). */
    public function upsert(array #[\SensitiveParameter] $row): void
    {
        $this->doUpsert($row, false);
    }

    /** Upsert that revives soft-delete (sets deleted_at = NULL on conflict). */
    public function upsertRevive(array #[\SensitiveParameter] $row): void
    {
        $this->doUpsert($row, true);
    }

    /** Internal helper for both modes; when $revive = true it clears deleted_at on conflict. */
    private function doUpsert(array $row, bool $revive): void
    {
        $row  = $this->filterCols($this->normalizeInputRow($row));
        if (!$row) return;

        $keys = [[UPSERT_KEYS_ARRAY]];
        if (!$keys) {
            $uqs = Definitions::uniqueKeys();
            $keys = (is_array($uqs) && isset($uqs[0]) && is_array($uqs[0]) && $uqs[0]) ? $uqs[0] : $this->pkColumns(Definitions::class);
        }

        $updCols = [[UPSERT_UPDATE_COLUMNS_ARRAY]];
        $updCols = array_values(array_diff($updCols, array_merge($this->pkColumns(Definitions::class), $keys)));

        // Revive policy
        [$row, $updCols] = $this->applyUpsertRevivePolicy($row, $updCols, $revive);

        [$sql, $params] = UpsertBuilder::buildRow(
            $this->db,
            Definitions::table(),
            $row,
            $keys,
            $updCols,
            Definitions::updatedAtColumn()
        );
        $this->db->execute($sql, $params);
    }

    /** Upsert by keys – default behavior keeps soft-delete. */
    public function upsertByKeys(array $row, array $keys, array $updateColumns = []): void
    {
        $this->doUpsertByKeys($row, $keys, $updateColumns, false);
    }

    /** Upsert by keys and revive soft-deleted rows (deleted_at=NULL on conflict). */
    public function upsertByKeysRevive(array $row, array $keys, array $updateColumns = []): void
    {
        $this->doUpsertByKeys($row, $keys, $updateColumns, true);
    }

    private function doUpsertByKeys(array $row, array $keys, array $updateColumns, bool $revive): void
    {
        $row  = $this->filterCols($this->normalizeInputRow($row));
        if (!$row && !$keys) return;

        // ensure key values exist in the row (fill from provided keys when missing)
        $isAssoc = $keys && array_keys($keys) !== range(0, count($keys)-1);
        $keyCols = $isAssoc ? array_keys($keys) : array_values($keys);
        if ($isAssoc) foreach ($keyCols as $kc) if (!array_key_exists($kc,$row) && array_key_exists($kc,$keys)) $row[$kc]=$keys[$kc];

        $updCols = array_values(array_diff($updateColumns, array_merge($this->pkColumns(Definitions::class), $keyCols)));

        // Revive policy
        [$row, $updCols] = $this->applyUpsertRevivePolicy($row, $updCols, $revive);

        [$sql, $params] = UpsertBuilder::buildByKeys(
            $this->db,
            Definitions::table(),
            $row,
            $keyCols,
            $updCols,
            Definitions::updatedAtColumn()
        );
        $this->db->execute($sql, $params);
    }

    /** Batch upsert - default (no revive). */
    public function upsertMany(array $rows): int {
        $rows = array_values(array_filter(
            array_map(fn($r) => is_array($r) ? $this->filterCols($this->normalizeInputRow($r)) : null, $rows),
            fn($r) => !empty($r)
        ));
        if (!$rows) { return 0; }

        if (class_exists(\BlackCat\Database\BulkUpsertRepository::class) && [[UPSERT_KEYS_ARRAY]] !== []) {
            $bulk = new \BlackCat\Database\BulkUpsertRepository($this->db, \[[NAMESPACE]]\Definitions::table());
            return $bulk->upsertMany($rows, [[UPSERT_KEYS_ARRAY]], [[UPSERT_UPDATE_COLUMNS_ARRAY]]);
        }

        $n = 0;
        foreach ($rows as $r) { $this->doUpsert((array)$r, false); $n++; }
        return $n;
    }

    /** Batch upsert variant that revives soft-deleted rows. */
    public function upsertManyRevive(array $rows): int {
        $rows = array_values(array_filter($rows, 'is_array'));
        if (!$rows) { return 0; }

        // Revive policy is per row - keep it simple
        $n = 0;
        foreach ($rows as $r) { $this->doUpsert((array)$r, true); $n++; }
        return $n;
    }

    // --- UPDATE / DELETE / RESTORE ------------------------------------------

    public function updateById(int|string|array $id, array #[\SensitiveParameter] $row): int {
        $row = $this->normalizeInputRow($row);

        $tbl   = Ident::qi($this->db, Definitions::table());
        $pkCols= $this->pkColumns(Definitions::class);
        $idMap = $this->normalizePkInput($id, $pkCols);

        $verCol = Definitions::versionColumn();
        $updAt  = Definitions::updatedAtColumn();

        $hasExpectedVersion = $verCol && array_key_exists($verCol, $row);
        $expectedVersion = $hasExpectedVersion ? $row[$verCol] : null;
        if ($hasExpectedVersion) unset($row[$verCol]);

        $row = $this->filterCols($row);

        $params  = [];
        $wherePk = $this->buildPkWhere('', $idMap, $params, 'pk_');

        $pkSet   = array_fill_keys($pkCols, true);
        $assign  = [];

        // payload columns (excluding PK)
        foreach ($row as $k => $v) {
            if (isset($pkSet[$k])) continue;
            $assign[]     = Ident::q($this->db, $k) . ' = :' . $k;
            $params[$k]   = $v;
        }

        // touch – verze/updated_at
        if ($verCol && $this->isNumericVersion()) {
            $assign[] = Ident::q($this->db, $verCol) . ' = ' . Ident::q($this->db, $verCol) . ' + 1';
        }
        if ($updAt && !array_key_exists($updAt, $row)) {
            $assign[] = Ident::q($this->db, $updAt) . ' = CURRENT_TIMESTAMP';
        }

        if (!$assign) return 0;

        $sql = "UPDATE {$tbl} SET " . implode(', ', $assign) . " WHERE {$wherePk}";
        if ($verCol && $hasExpectedVersion) {
            $sql .= ' AND ' . Ident::q($this->db, $verCol) . ' = :expected_version';
            $params['expected_version'] = is_numeric($expectedVersion) ? (int)$expectedVersion : $expectedVersion;
        }

        return $this->db->execute($sql, $params);
    }

    public function deleteById(int|string|array $id): int {
        $tbl = Ident::qi($this->db, Definitions::table());
        $pk  = $this->normalizePkInput($id, $this->pkColumns(Definitions::class));
        $params=[]; $wherePk = $this->buildPkWhere('', $pk, $params, 'pk_');

        if ($soft = Definitions::softDeleteColumn()) {
            $set = Ident::q($this->db, $soft) . ' = CURRENT_TIMESTAMP';
            if (($updAt = Definitions::updatedAtColumn()) && $updAt !== $soft) {
                $set .= ', ' . Ident::q($this->db, $updAt) . ' = CURRENT_TIMESTAMP';
            }
            return $this->db->execute("UPDATE {$tbl} SET {$set} WHERE {$wherePk}", $params);
        }
        return $this->db->execute("DELETE FROM {$tbl} WHERE {$wherePk}", $params);
    }

    public function restoreById(int|string|array $id): int {
        $tbl = Ident::qi($this->db, Definitions::table());
        $pk  = $this->normalizePkInput($id, $this->pkColumns(Definitions::class));
        $params=[]; $wherePk = $this->buildPkWhere('', $pk, $params, 'pk_');

        $soft = Definitions::softDeleteColumn(); if (!$soft) return 0;
        $set = Ident::q($this->db, $soft) . ' = NULL';
        if (($updAt = Definitions::updatedAtColumn()) && $updAt !== $soft) {
            $set .= ', ' . Ident::q($this->db, $updAt) . ' = CURRENT_TIMESTAMP';
        }
        return $this->db->execute("UPDATE {$tbl} SET {$set} WHERE {$wherePk}", $params);
    }

    // --- READ / PAGE / LOCK --------------------------------------------------

    public function findById(int|string|array $id): ?array {
        $view = Ident::qi($this->db, Definitions::contractView());
        $tbl  = Ident::qi($this->db, Definitions::table());

        $params=[]; $idMap = $this->normalizePkInput($id, $this->pkColumns(Definitions::class));

        // 1) view
        try {
            $where = $this->buildPkWhere('t', $idMap, $params, 'pk_');
            $rows  = $this->db->fetchAll("SELECT t.* FROM {$view} t WHERE {$where} AND ".$this->softGuard('t'), $params);
            if ($rows) return $rows[0];
        } catch (\Throwable) { /* fallback below */ }

        // 2) table fallback
        $where = $this->buildPkWhere('', $idMap, $params, 'pk_');
        $sql   = "SELECT * FROM {$tbl} WHERE {$where}";
        $guard = $this->softGuard('');
        if ($guard !== '1=1') $sql .= ' AND ' . $guard;
        return $this->db->fetch($sql, $params) ?: null;
    }

    /**
     * Find multiple rows by a list of primary keys. For composite PK expect maps (['col'=>val,...]).
     * @param array<int,int|string|array> $ids
     * @return array<int,array<string,mixed>>
     */
    public function findAllByIds(array $ids): array
    {
        if (!$ids) return [];
        $tbl = Ident::qi($this->db, Definitions::table());
        $pkCols = $this->pkColumns(Definitions::class);
        $whereParts = [];
        $params = [];
        $i = 0;

        if (count($pkCols) === 1) {
            // fast path: IN (:p0,:p1,...)
            $col = Ident::q($this->db, $pkCols[0]);
            $guard = $this->softGuard('');
            $all = [];
            $ids = array_values($ids);
            $chunk = 1000;
            for ($o = 0; $o < count($ids); $o += $chunk) {
                $slice = array_slice($ids, $o, $chunk);
                $ph=[]; $params=[]; $j=0;
                foreach ($slice as $v) { $k="p{$o}_{$j}"; $ph[]=":$k"; $params[$k]=$v; $j++; }
                $sql = "SELECT * FROM {$tbl} WHERE {$col} IN (" . implode(',', $ph) . ")";
                if ($guard !== '1=1') $sql .= ' AND ' . $guard;
                $all = array_merge($all, $this->db->fetchAll($sql, $params));
            }
            return $all;
        }

        foreach ($ids as $id) {
            $map = $this->normalizePkInput($id, $pkCols);
            $whereParts[] = '(' . $this->buildPkWhere('', $map, $params, 'b'.$i.'_') . ')';
            $i++;
        }

        $sql = "SELECT * FROM {$tbl} WHERE " . implode(' OR ', $whereParts);
        $guard = $this->softGuard('');
        if ($guard !== '1=1') $sql .= ' AND ' . $guard;

        return $this->db->fetchAll($sql, $params);
    }

    /**
     * Fetch a record by a unique combination (aka "business keys").
     * @param array<string,mixed> $keyValues assoc: sloupec => hodnota
     * @return array<string,mixed>|Dto|null
     */
    public function getByUnique(array $keyValues, bool $asDto = false): array|Dto|null
    {
        if (!$keyValues) return null;
        $view = Ident::qi($this->db, Definitions::contractView());

        $parts  = [];
        $params = [];
        foreach ($keyValues as $col => $val) {
            $colQ = 't.' . Ident::q($this->db, (string)$col);
            if ($val === null) {
                $parts[] = $colQ . ' IS NULL';
            } else {
                $ph = 'u_' . $col;
                $parts[] = $colQ . ' = :' . $ph;
                $params[$ph] = $val;
            }
        }
        $where = '(' . implode(' AND ', $parts) . ') AND ' . $this->softGuard('t');

        $row = $this->db->fetch("SELECT t.* FROM {$view} t WHERE {$where} LIMIT 1", $params) ?: null;
        return $this->mapReturn($row, $asDto);
    }

    public function exists(string $whereSql = '1=1', array $params = []): bool {
        $view = Ident::qi($this->db, Definitions::contractView());
        $where = '(' . $whereSql . ') AND ' . $this->softGuard('t');
        return (bool)$this->db->fetchOne("SELECT 1 FROM {$view} t WHERE {$where} LIMIT 1", $params);
    }

    public function count(string $whereSql = '1=1', array $params = []): int {
        $view = Ident::qi($this->db, Definitions::contractView());
        $where = '(' . $whereSql . ') AND ' . $this->softGuard('t');
        return (int)$this->db->fetchOne("SELECT COUNT(*) FROM {$view} t WHERE {$where}", $params);
    }

    /**
     * @return array{items:array<int,array<string,mixed>>,total:int,page:int,perPage:int}
     */
    public function paginate(object $criteria): array {
        if (!$criteria instanceof Criteria) throw new \InvalidArgumentException('Expected ' . Criteria::class);
        $c = $criteria;

        [$where, $params, $order, $limit, $offset, $joins] = $c->toSql(true);
        $where = '(' . $where . ') AND ' . $this->softGuard('t');
        $order = $order ?: (Definitions::defaultOrder() ?? (Definitions::pk() . ' DESC'));
        $orderSql = $this->buildOrderBy($order, Definitions::columns(), $this->db);

        $view = Ident::qi($this->db, Definitions::contractView());
        $total = (int)$this->db->fetchOne("SELECT COUNT(*) FROM {$view} t {$joins} WHERE {$where}", $params);
        $items = $this->db->fetchAll("SELECT t.* FROM {$view} t {$joins} WHERE {$where}" . ($orderSql ? ' '.$orderSql : '') . " LIMIT {$limit} OFFSET {$offset}", $params);
        return ['items'=>$items, 'total'=>$total, 'page'=>$c->page(), 'perPage'=>$c->perPage()];
    }

    /** @param 'wait'|'nowait'|'skip_locked' $mode
     * @param 'update'|'share' $strength
    */
    public function lockById(int|string|array $id, string $mode = 'wait', string $strength = 'update'): ?array {
        $tbl = Ident::qi($this->db, Definitions::table());
        $params=[]; $where = $this->buildPkWhere('', $this->normalizePkInput($id, $this->pkColumns(Definitions::class)), $params, 'pk_');
        $guard = $this->softGuard('');
        $sql = "SELECT * FROM {$tbl} WHERE {$where}";
        if ($guard !== '1=1') { $sql .= ' AND ' . $guard; }

        $dialect = $this->db->getDialect(); // 'postgres' | 'mysql' | 'mariadb' ...
        $for = 'FOR UPDATE';
        if ($strength === 'share') {
            if ($dialect === 'postgres' || $dialect === 'mysql') { $for = 'FOR SHARE'; }
            else { $for = 'LOCK IN SHARE MODE'; } // legacy MySQL/MariaDB
        }
        $sql .= ' ' . $for . LockMode::compile($this->db, $mode);
        $row = $this->db->fetch($sql, $params);
        return $row ?: null;
    }

    // --- Keyset / seek pagination -------------------------------------------

    public function paginateBySeek($criteria, array $order, ?array $cursor, int $limit): array {
        if (!$criteria instanceof Criteria) throw new \InvalidArgumentException('Expected ' . Criteria::class);

        [$where, $params, /*$orderIgnored*/, /*$lim*/, /*$off*/, $joins] = $criteria->toSql(true);
        $orderSpec = [
            'col' => $order['col'],
            'dir' => strtolower($order['dir'] ?? 'desc'),
            'pk'  => $order['pk'],
        ];

        return KeysetPaginator::paginate(
            $this->db,
            Definitions::contractView(),
            $where,
            $params,
            $joins,
            $this->softGuard('t'),
            $orderSpec,
            $cursor,
            $limit
        );
    }

    public function existsById(int|string|array $id): bool {
        $params=[]; $where = $this->buildPkWhere('t', $this->normalizePkInput($id, $this->pkColumns(Definitions::class)), $params, 'pk_');
        $view = Ident::qi($this->db, Definitions::contractView());
        $where = '(' . $where . ') AND ' . $this->softGuard('t');
        return (bool)$this->db->fetchOne("SELECT 1 FROM {$view} t WHERE {$where} LIMIT 1", $params);
    }

    // === Generated unique helpers (per table UNIQUE/PK) ===
    [[UNIQUE_HELPERS]]
}
'@
}
