@{
  File   = 'src/Criteria.php'
  Tokens = @(
    'NAMESPACE','FILTERABLE_COLUMNS_ARRAY','SEARCHABLE_COLUMNS_ARRAY',
    'DEFAULT_PER_PAGE','MAX_PER_PAGE'
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

/**
 * Bezpečný builder WHERE/ORDER/LIMIT + joiny.
 * - whitelist filtrů: [[FILTERABLE_COLUMNS_ARRAY]]
 * - whitelist LIKE:   [[SEARCHABLE_COLUMNS_ARRAY]]
 * Podporované tvary:
 *   addFilter('status', 'paid');                    // =
 *   addFilter('id', [1,2,3]);                       // IN (...)
 *   where('created_at','>=','2025-01-01');         // operátor
 *   between('created_at','2025-01-01','2025-01-31');
 *   isNull('deleted_at'); isNotNull('deleted_at');
 *   search('foo');                                  // OR přes whitelist
 *   join('LEFT JOIN vw_users u ON u.id = t.user_id', [':x'=>123]);
 *   whereRaw('(t.total - t.discount_total) > :min', [':min'=>0]);
 */
final class Criteria {
    /** @var array<string,mixed> rovnost/IN */
    private array $filters = [];
    /** @var array<int,array{col:string,op:string,val:mixed}> */
    private array $ops = [];
    /** @var array<int,array{col:string,from:mixed,to:mixed}> */
    private array $ranges = [];
    /** @var array<int,array{col:string,neg:bool}> */
    private array $nulls = [];
    /** @var array<int,array{col:string,dir:string}> */
    private array $sort = [];
    /** @var array<int,string> */
    private array $joins = [];
    /** @var array<string,mixed> */
    private array $joinParams = [];
    /** @var array<int,array{sql:string,params:array}> */
    private array $raw = [];

    private ?string $search = null;
    private int $page = 1;
    private int $perPage = [[DEFAULT_PER_PAGE]];

    public function addFilter(string $col, mixed $value): self {
        $this->filters[$col] = $value; return $this;
    }
    public function where(string $col, string $op, mixed $val): self {
        $this->ops[] = ['col'=>$col,'op'=>strtoupper(trim($op)),'val'=>$val]; return $this;
    }
    public function between(string $col, mixed $from, mixed $to): self {
        $this->ranges[] = ['col'=>$col,'from'=>$from,'to'=>$to]; return $this;
    }
    public function isNull(string $col): self {
        $this->nulls[] = ['col'=>$col,'neg'=>false]; return $this;
    }
    public function isNotNull(string $col): self {
        $this->nulls[] = ['col'=>$col,'neg'=>true]; return $this;
    }
    public function whereRaw(string $sql, array $params = []): self {
        $this->raw[] = ['sql'=>$sql,'params'=>$params]; return $this;
    }

    public function orderBy(string $col, string $dir = 'ASC'): self {
        $this->sort[] = ['col'=>$col,'dir'=>$dir]; return $this;
    }
    public function search(?string $q): self {
        $this->search = $q !== null && $q !== '' ? $q : null; return $this;
    }
    public function setPage(int $p): self { $this->page = max(1, $p); return $this; }
    public function setPerPage(int $n): self {
        $n = max(1, min([[MAX_PER_PAGE]], $n)); $this->perPage = $n; return $this;
    }

    /** Přidej JOIN (string fragment – generátor může vkládat přes Joins třídu). */
    public function join(string $sqlJoinFragment, array $params = []): self {
        if ($sqlJoinFragment !== '') { $this->joins[] = $sqlJoinFragment; }
        foreach ($params as $k=>$v) { $this->joinParams[$k] = $v; }
        return $this;
    }

    public function pageNumber(): int { return $this->page; }
    public function perPage(): int { return $this->perPage; }
    public function page(): int { return $this->page; }

    /**
     * @return array{0:string,1:array,2:?string,3:int,4:int,5:string}
     */
    public function toSql(bool $viewMode = false): array {
        $where = [];
        $params = [];

        // Pokud jedeme přes view s aliasem "t" (repo volá toSql(true)),
        // prefiksuj whitelisted sloupce "t." v WHERE, aby nedošlo ke kolizi s JOINy.
        $ref = static function (string $c) use ($viewMode): string {
            if ($c === '') { return $c; }
            // necháme uživatelské výrazy s tečkou být (t.col / j0.col...)
            if (strpos($c, '.') !== false) { return $c; }
            return $viewMode ? 't.' . $c : $c;
        };

        $allowed = array_fill_keys([[FILTERABLE_COLUMNS_ARRAY]], true);

        // rovnosti/IN
        foreach ($this->filters as $col=>$val) {
            if (!isset($allowed[$col])) { continue; }
            if (is_array($val) && $val) {
                $ph = []; $i=0;
                foreach ($val as $v) { $k=":$col"."_in_$i"; $ph[]=$k; $params[$k]=$v; $i++; }
                $where[] = $ref($col) . " IN (".implode(',', $ph).")";
            } elseif ($val === null) {
                $where[] = $ref($col) . " IS NULL";
            } else {
                $k=":$col"; $params[$k]=$val; $where[] = $ref($col) . " = $k";
            }
        }

        // operátory
        foreach ($this->ops as $i=>$o) {
            [$col,$op,$val] = [$o['col'],$o['op'],$o['val']];
            if (!isset($allowed[$col])) { continue; }
            // special-case ILIKE (PG) -> fallback na LIKE
            if ($op === 'ILIKE') { $op = 'LIKE'; }
            $k=":op_{$i}_$col"; $params[$k]=$val;
            $where[] = $ref($col) . " $op $k";
        }

        // between
        foreach ($this->ranges as $i=>$r) {
            $col = $r['col']; if (!isset($allowed[$col])) { continue; }
            $k1=":b_{$i}_from_$col"; $k2=":b_{$i}_to_$col";
            $params[$k1]=$r['from']; $params[$k2]=$r['to'];
            $where[] = $ref($col) . " BETWEEN $k1 AND $k2";
        }

        // IS NULL / IS NOT NULL
        foreach ($this->nulls as $n) {
            $col=$n['col']; if (!isset($allowed[$col])) { continue; }
            $where[] = $ref($col) . ($n['neg'] ? ' IS NOT NULL' : ' IS NULL');
        }

        // search přes whitelist LIKE
        if ($this->search !== null) {
            $searchCols = [[SEARCHABLE_COLUMNS_ARRAY]];
            $likeParts = []; $i=0;
            foreach ($searchCols as $c) {
                if ($c === '' || !isset($allowed[$c])) continue;
                $k=":s$i"; $params[$k] = '%'.$this->search.'%'; $i++;
                $likeParts[] = $ref($c) . " LIKE $k";
            }
            if ($likeParts) { $where[] = '('.implode(' OR ', $likeParts).')'; }
        }

        // raw
        foreach ($this->raw as $r) {
            $where[] = '('.$r['sql'].')';
            foreach ($r['params'] as $k=>$v) { $params[$k]=$v; }
        }

        if (!$where) { $where = ['1=1']; }

        // order
        $order = null;
        if ($this->sort) {
            $safeCols = array_fill_keys([[FILTERABLE_COLUMNS_ARRAY]], true);
            $parts = [];
            foreach ($this->sort as $s) {
                [$c,$d] = [$s['col'], strtoupper($s['dir'] ?? 'ASC')];
                if (!isset($safeCols[$c])) { continue; }
                if (!in_array($d, ['ASC','DESC'], true)) { $d='ASC'; }
                // ORDER necháváme bez prefixu – escapuje a aliasuje se až v repo->buildOrderBy()
                $parts[] = "$c $d";
            }
            if ($parts) { $order = implode(',', $parts); }
        }

        $limit = $this->perPage;
        $offset = ($this->page - 1) * $this->perPage;

        $joins = '';
        if ($this->joins) { $joins = implode(' ', $this->joins); }
        if ($this->joinParams) { $params = $this->joinParams + $params; }

        return [implode(' AND ', $where), $params, $order, $limit, $offset, $joins];
    }
}
'@
}
