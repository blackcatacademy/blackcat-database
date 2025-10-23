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
 * Bezpečný builder WHERE/ORDER/LIMIT.
 * - whitelist filtrů: [[FILTERABLE_COLUMNS_ARRAY]]
 * - whitelist pro LIKE hledání: [[SEARCHABLE_COLUMNS_ARRAY]]
 */
final class Criteria {
    /** @var array<string,mixed> */
    private array $filters = [];
    /** @var array<int,array{col:string,dir:string}> */
    private array $sort = [];
    private ?string $search = null;
    private int $page = 1;
    private int $perPage = [[DEFAULT_PER_PAGE]];

    public function addFilter(string $col, mixed $value): self {
        $this->filters[$col] = $value; return $this;
    }
    public function orderBy(string $col, string $dir = 'ASC'): self {
        $this->sort[] = ['col'=>$col,'dir'=>$dir]; return $this;
    }
    public function search(?string $q): self {
        $this->search = $q !== null && $q !== '' ? $q : null; return $this;
    }
    public function setPage(int $p): self {
        $this->page = max(1, $p); return $this;
    }
    public function setPerPage(int $n): self {
        $n = max(1, min([[MAX_PER_PAGE]], $n));
        $this->perPage = $n; return $this;
    }
    public function pageNumber(): int { return $this->page; }
    public function perPage(): int { return $this->perPage; }
    public function page(): int { return $this->page; }

    /**
     * @return array{0:string,1:array,2:?string,3:int,4:int,5:string} [where, params, order, limit, offset, joins]
     */
    public function toSql(bool $viewMode = false): array {
        $where = [];
        $params = [];

        // filtry (rovnosti / IN)
        $allowed = array_fill_keys([[FILTERABLE_COLUMNS_ARRAY]], true);
        foreach ($this->filters as $col=>$val) {
            if (!isset($allowed[$col])) { continue; }
            if (is_array($val) && $val) {
                $ph = [];
                foreach ($val as $i=>$v) { $k=":$col"."_$i"; $ph[]=$k; $params[$k]=$v; }
                $where[] = "$col IN (".implode(',', $ph).")";
            } elseif ($val === null) {
                $where[] = "$col IS NULL";
            } else {
                $k=":$col"; $params[$k]=$val; $where[] = "$col = $k";
            }
        }

        // fulltext/LIKE (přes whitelist)
        if ($this->search !== null) {
            $searchCols = [[SEARCHABLE_COLUMNS_ARRAY]];
            $likeParts = [];
            foreach ($searchCols as $i=>$c) {
                if ($c === '') continue;
                $k=":s$i"; $params[$k] = '%'.$this->search.'%';
                $likeParts[] = "$c LIKE $k";
            }
            if ($likeParts) { $where[] = '('.implode(' OR ', $likeParts).')'; }
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
                $parts[] = "$c $d";
            }
            if ($parts) { $order = implode(',', $parts); }
        }

        $limit = $this->perPage;
        $offset = ($this->page - 1) * $this->perPage;

        return [implode(' AND ', $where), $params, $order, $limit, $offset, ''];
    }
}
'@
}
