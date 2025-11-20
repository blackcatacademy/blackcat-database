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

namespace BlackCat\Database\Support;

use BlackCat\Database\Tenancy\TenantScope;
use BlackCat\Database\Support\Search;
use BlackCat\Core\Database;

/**
 * Criteria – safe, compact, developer-friendly builder for WHERE/ORDER/LIMIT/JOIN fragments
 * targeting MySQL/MariaDB and PostgreSQL.
 *
 * Key features:
 * - Column whitelists (filterable/searchable/sortable) and joinable entities.
 * - Safe parameters (unique placeholders) and optional identifier quoting.
 * - Full-text mode (PG to_tsvector/plainto_tsquery, MySQL MATCH ... AGAINST).
 * - Seek pagination via PK (no OFFSET drift) + traditional page/perPage.
 * - Soft delete helpers (withTrashed/onlyTrashed) and multi-tenant filtering.
 *
 * `toSql()` returns a 6-tuple:
 *   [0] string  $whereSql   (e.g. "t.tenant_id = :ten_tenant_id_0 AND ...")
 *   [1] array   $params     (map of :param => value)
 *   [2] ?string $orderBy    (e.g. "t.id DESC NULLS LAST" or null)
 *   [3] int     $limit
 *   [4] int     $offset
 *   [5] string  $joinsSql   (JOIN fragments)
 *
 * @phpstan-type WhereParam array<string,mixed>
 * @phpstan-type SortSpec array{col:string,dir:string,nullsLast:bool}
 * @phpstan-type RangeSpec array{col:string,from:mixed,to:mixed}
 * @phpstan-type OpSpec array{col:string,op:string,val:mixed}
 * @phpstan-type NullSpec array{col:string,neg:bool}
 */
class Criteria
{
    /** Optional Database instance for driver-aware quoting and dialect inference. */
    private ?Database $db = null;

    /** ---- Override these in subclasses per table/view ---- */
    /** @return list<string> e.g. ['id','tenant_id','status','created_at'] */
    protected function filterable(): array { return []; }

    /** @return list<string> e.g. ['order_no','customer_email'] */
    protected function searchable(): array { return []; }

    /** (NEW) falls back to filterable() if not overridden */
    /** @return list<string> */
    protected function sortable(): array { return $this->filterable(); }

    /** (NEW) whitelist of joinable entities: ['orders'=>'o', 'users'=>'u'], etc. */
    /** @return array<string,string> table => alias */
    protected function joinable(): array { return []; }

    protected function defaultPerPage(): int { return 20; }
    protected function maxPerPage(): int { return 200; }

    /** @var array<string,mixed> rovnost/IN */
    private array $filters = [];
    /** @var list<OpSpec> */
    private array $ops = [];
    /** @var list<RangeSpec> */
    private array $ranges = [];
    /** @var list<NullSpec> */
    private array $nulls = [];
    /** @var list<SortSpec> */
    private array $sort = [];
    /** @var list<string> */
    private array $joins = [];
    /** @var WhereParam */
    private array $joinParams = [];
    /** @var list<array{sql:string,params:WhereParam}> */
    private array $raw = [];

    private ?string $search = null;
    private bool $useFulltext = false;
    private string $fulltextDict = 'simple'; // PG dictionary

    private int $page = 1;
    private int $perPage;
    private ?int $explicitLimit = null;
    private ?int $explicitOffset = null;

    /** @var 'mysql'|'postgres' */
    private string $dialect = 'mysql';
    private bool $caseInsensitiveLike = true;

    private ?string $tenantCol = null;
    /** @var int|string|list<int|string>|null */
    private int|string|array|null $tenantVal = null;

    private ?string $seekPk = null;
    private mixed $seekAfter = null;
    /** @var 'ASC'|'DESC' */
    private string $seekDir = 'DESC';
    private bool $seekInclusive = false;

    /** @var WhereParam */
    private array $extraParams = [];

    private ?string $softDeleteCol = null;
    private bool $withTrashed = false;
    private bool $onlyTrashed = false;

    // (NEW) optional identifier quoting
    private bool $quoteIdentifiers = false;

    // (NEW) global counter for unique placeholders
    private int $paramSeq = 0;

    public function __construct()
    {
        $this->perPage = $this->defaultPerPage();
    }

    /* -------------------- Mutators -------------------- */

    public function setDialectFromDatabase(\BlackCat\Core\Database $db): self
    {
        $this->db = $db; // enable driver-aware quoteIdent()
        $drv = \strtolower((string)$db->driver());
        return $this->setDialect($drv === 'pgsql' ? 'postgres' : ($drv === 'mariadb' ? 'mysql' : $drv));
    }
 
    /** Optional Database injection without changing the configured dialect. */
    public function withDatabase(Database $db): self
    {
        $this->db = $db;
        return $this;
    }

    /** @param non-empty-string $dialect 'mysql'|'postgres'|'mariadb' */
    public function setDialect(string $dialect): self
    {
        $d = \strtolower(\trim($dialect));
        $this->dialect = ($d === 'mariadb') ? 'mysql' : (($d === 'postgres') ? 'postgres' : 'mysql');
        return $this;
    }

    /** (NEW) toggles identifier quoting (`t`.`col` / "t"."col") */
    public function enableIdentifierQuoting(bool $on = true): self
    {
        $this->quoteIdentifiers = $on;
        return $this;
    }

    /** Disable if you need case-sensitive LIKE on MySQL (PG ILIKE is used only when CI is on). */
    public function useCaseInsensitiveLike(bool $on = true): self
    {
        $this->caseInsensitiveLike = $on;
        return $this;
    }

    /** (NEW) Enables full-text search (when an index exists) */
    public function useFulltext(bool $on = true, string $pgDictionary = 'simple'): self
    {
        $this->useFulltext = $on;
        $this->fulltextDict = $pgDictionary;
        return $this;
    }

    /** Safe limit/offset (negative inputs are clamped to 0) */
    public function limit(int $n): self { $this->explicitLimit  = \max(0, $n); return $this; }
    public function offset(int $n): self { $this->explicitOffset = \max(0, $n); return $this; }

    /** JSON contains – generates unique parameters to avoid collisions. */
    public function whereJsonContains(string $jsonCol, array $subset): self
    {
        if (!\in_array($jsonCol, $this->filterable(), true)) return $this;
        $dial = $this->dialect;
        $r = \BlackCat\Database\Support\JsonFilters::contains($dial, $jsonCol, $subset);
        // Prefer the shape with 'params'; otherwise keep the original behavior (BC).
        if (isset($r['params']) && \is_array($r['params'])) {
            return $this->whereRaw($r['expr'], $r['params']);
        }
        $needleKey = $this->uniqueParam(':json_contains_');
        return $this->whereRaw($r['expr'], [$needleKey => $r['param'] ?? $subset]);
    }

    /** JSON get-text equals – unique parameters (path + value). */
    public function whereJsonTextEquals(string $jsonCol, string $path, string $equals): self
    {
        if (!\in_array($jsonCol, $this->filterable(), true)) return $this;
        $dial = $this->dialect;
        $r = \BlackCat\Database\Support\JsonFilters::getText($dial, $jsonCol, $path);
        // 'expr' typically already contains the path; simply append the comparison value:
        $params = [];
        if (isset($r['params']) && \is_array($r['params'])) {
            $params = $r['params'];
        }
        $kVal  = $this->uniqueParam(':json_text_');
        $params[$kVal] = $equals;
        return $this->whereRaw('('.$r['expr'].' = '.$kVal.')', $params);
    }

    /** Stable (whitelisted) ORDER BY for tabular listings. */
    public function orderByTable(string $col, string $dir='ASC', bool $nullsLast=false): self
    {
        return $this->orderBySafe($col, $dir, $nullsLast);
    }

    public function addFilter(string $col, mixed $value): self
    {
        $this->filters[$col] = $value;
        return $this;
    }

    /**
     * General WHERE condition with an operator.
     * Allowed operators: =, <>, !=, >, >=, <, <=, LIKE, ILIKE, IN, NOT IN
     * (ILIKE available only on PG; otherwise remapped to LIKE based on caseInsensitiveLike)
     */
    public function where(string $col, string $op, mixed $val): self
    {
        $op = \strtoupper(\trim($op));
        $allowedOps = ['=','<>','!=','>','>=','<','<=','LIKE','ILIKE','IN','NOT IN'];
        if (!\in_array($op, $allowedOps, true)) {
            $op = '=';
        }

        if (($op === 'IN' || $op === 'NOT IN') && \is_array($val)) {
            if ($val === []) {
                // IN () => 1=0, NOT IN () => 1=1
                $sql = ($op === 'IN') ? '1=0' : '1=1';
                return $this->whereRaw($sql);
            }
            $ph = []; $i = 0; $params = [];
            foreach ($val as $v) {
                $k = $this->paramKey("opIn", $col, $i++);
                $ph[] = $k;
                $params[$k] = $v;
            }
            $sql = $this->refCol($col, false) . " {$op} (" . \implode(',', $ph) . ")";
            return $this->whereRaw($sql, $params);
        }

        $this->ops[] = ['col'=>$col,'op'=>$op,'val'=>$val];
        return $this;
    }

    public function between(string $col, mixed $from, mixed $to): self
    {
        $this->ranges[] = ['col'=>$col,'from'=>$from,'to'=>$to];
        return $this;
    }

    public function isNull(string $col): self      { $this->nulls[] = ['col'=>$col,'neg'=>false]; return $this; }
    public function isNotNull(string $col): self   { $this->nulls[] = ['col'=>$col,'neg'=>true];  return $this; }

    public function whereRaw(string $sql, array $params = []): self
    {
        if ($sql !== '') {
            $this->raw[] = ['sql'=>$sql,'params'=>$params];
        }
        return $this;
    }
    public function andWhere(string $sql): self { return $this->whereRaw($sql); }

    public function bind(string $key, mixed $val): self
    {
        $this->extraParams[$key] = $val;
        return $this;
    }

    public function orderBySafe(string $col, string $dir = 'ASC', bool $nullsLast = false): self
    {
        $dirUp = \strtoupper(\trim($dir));
        $dirUp = \in_array($dirUp, ['ASC','DESC'], true) ? $dirUp : 'ASC';
        $this->sort[] = ['col'=>$col,'dir'=>$dirUp,'nullsLast'=>(bool)$nullsLast];
        return $this;
    }
    public function orderBy(string $col, string $dir = 'ASC'): self { return $this->orderBySafe($col, $dir, false); }

    public function search(?string $q): self
    {
        $this->search = ($q !== null && $q !== '') ? $q : null;
        return $this;
    }

    public function setPage(int $p): self
    {
        $this->page = \max(1, $p);
        return $this;
    }
    public function setPerPage(int $n): self
    {
        $n = \max(1, \min($this->maxPerPage(), $n));
        $this->perPage = $n;
        return $this;
    }

    public function join(string $sqlJoinFragment, array $params = []): self
    {
        if ($sqlJoinFragment !== '') { $this->joins[] = $sqlJoinFragment; }
        foreach ($params as $k=>$v) { $this->joinParams[$k] = $v; }
        return $this;
    }

    /** (NEW) Safe JOIN builder with table/alias/column whitelist and identifier quoting. */
    public function joinSafe(string $table, string $alias, string $leftCol, string $op, string $rightCol, string $type='INNER'): self
    {
        $typeU = \strtoupper($type);
        if (!\in_array($typeU, ['INNER','LEFT','RIGHT','FULL'], true)) { $typeU = 'INNER'; }
        // Compatibility: FULL JOIN only on PostgreSQL – downgrade to LEFT elsewhere
        if ($typeU === 'FULL' && $this->dialect !== 'postgres') {
            $typeU = 'LEFT';
        }
        $allowed = $this->joinable(); // table => alias
        // Allow either the exact table name (key) or an alias present in values
        if ($allowed && !\array_key_exists($table, $allowed) && !\in_array($alias, $allowed, true)) {
            return $this; // ignore unknown join target
        }

        $op = \strtoupper(\trim($op));
        if (!\in_array($op, ['=','<>','!=','>','>=','<','<='], true)) { $op = '='; }

        $l = $this->refCol($leftCol, true);
        $r = $this->refCol($rightCol, true);
        $t = $this->quoteIdent($table) . ' ' . $this->quoteIdent($alias);
        $this->joins[] = "{$typeU} JOIN {$t} ON {$l} {$op} {$r}";
        return $this;
    }

    /** @param int|string|list<int|string> $tenantId */
    public function tenant(int|string|array $tenantId, string $column = 'tenant_id'): self
    {
        if (!\in_array($column, $this->filterable(), true)) {
            throw new \LogicException(
                "Tenant column '{$column}' must be whitelisted via filterable() before applying tenant scope."
            );
        }
        $this->tenantCol = $column;
        $this->tenantVal = \is_array($tenantId) ? \array_values($tenantId) : $tenantId;
        return $this;
    }

    public function applyTenantScope(TenantScope $t, string $column = 'tenant_id'): self
    {
        return $this->tenant($t->idList(), $column);
    }

    public function seek(string $pkCol, mixed $after, string $dir = 'DESC', bool $inclusive = false): self
    {
        $this->seekPk = $pkCol;
        $this->seekAfter = $after;
        $d = \strtoupper($dir);
        $this->seekDir = ($d === 'ASC' ? 'ASC' : 'DESC');
        $this->seekInclusive = $inclusive;
        return $this;
    }

    public function pageNumber(): int { return $this->page; }
    public function perPage(): int { return $this->perPage; }
    public function page(): int { return $this->page; }

    /**
     * Builds the SQL fragments.
     *
     * @return array{0:string,1:array<string,mixed>,2:?string,3:int,4:int,5:string}
     */
    public function toSql(bool $viewMode = false): array
    {
        $where  = [];
        $params = [];

        $allowedFilter = \array_fill_keys($this->filterable(), true);
        $allowedSort   = \array_fill_keys($this->sortable(), true);

        // soft-delete
        if ($this->softDeleteCol !== null && isset($allowedFilter[$this->softDeleteCol])) {
            $col = $this->refCol($this->softDeleteCol, $viewMode);
            if ($this->onlyTrashed) {
                $where[] = "{$col} IS NOT NULL";
            } elseif (!$this->withTrashed) {
                $where[] = "{$col} IS NULL";
            }
        }

        // tenancy
        if ($this->tenantCol !== null && isset($allowedFilter[$this->tenantCol])) {
            $col = $this->tenantCol;
            if (\is_array($this->tenantVal)) {
                if (!$this->tenantVal) {
                    $where[] = '1=0';
                } else {
                    $ph = []; $i=0;
                    foreach ($this->tenantVal as $v) {
                        $k = $this->paramKey("ten", $col, $i++);
                        $ph[] = $k; $params[$k] = $v;
                    }
                    $where[] = $this->refCol($col, $viewMode) . " IN (" . \implode(',', $ph) . ")";
                }
            } else {
                $k = $this->paramKey("ten", $col, 0);
                $params[$k] = $this->tenantVal;
                $where[] = $this->refCol($col, $viewMode) . " = $k";
            }
        }

        // rovnosti/IN/NULL
        foreach ($this->filters as $col => $val) {
            if (!isset($allowedFilter[$col])) { continue; }
            if (\is_array($val)) {
                if ($val === []) {
                    $where[] = '1=0';
                } else {
                    $ph = []; $i=0;
                    foreach ($val as $v) {
                        $k = $this->paramKey($col, 'in', $i++);
                        $ph[] = $k; $params[$k] = $v;
                    }
                    $where[] = $this->refCol($col, $viewMode) . " IN (" . \implode(',', $ph) . ")";
                }
            } elseif ($val === null) {
                $where[] = $this->refCol($col, $viewMode) . " IS NULL";
            } else {
                $k = $this->paramKey($col, 'eq', 0);
                $params[$k] = $val;
                $where[] = $this->refCol($col, $viewMode) . " = $k";
            }
        }

        // Operators
        foreach ($this->ops as $i => $o) {
            [$col,$op,$val] = [$o['col'],$o['op'],$o['val']];
            if (!isset($allowedFilter[$col])) { continue; }
            if ($op === 'ILIKE' && !($this->dialect === 'postgres' && $this->caseInsensitiveLike)) {
                $op = 'LIKE';
            }
            $k = $this->paramKey("op{$i}", $col, 0);
            if ($op === 'LIKE' || $op === 'ILIKE') {
                $params[$k] = '%' . Search::escapeLike((string)$val) . '%';
                $where[] = $this->refCol($col, $viewMode) . " $op $k" . Search::escClause($this->dialect);
            } else {
                $params[$k] = $val;
                $where[] = $this->refCol($col, $viewMode) . " $op $k";
            }
        }

        // between
        foreach ($this->ranges as $i => $r) {
            $col = $r['col']; if (!isset($allowedFilter[$col])) { continue; }
            $k1 = $this->paramKey("b{$i}", $col, 1);
            $k2 = $this->paramKey("b{$i}", $col, 2);
            $params[$k1] = $r['from'];
            $params[$k2] = $r['to'];
            $where[] = $this->refCol($col, $viewMode) . " BETWEEN $k1 AND $k2";
        }

        // NULL/NOT NULL
        foreach ($this->nulls as $n) {
            $col = $n['col']; if (!isset($allowedFilter[$col])) { continue; }
            $where[] = $this->refCol($col, $viewMode) . ($n['neg'] ? ' IS NOT NULL' : ' IS NULL');
        }

        // search
        if ($this->search !== null) {
            if ($this->useFulltext && $this->searchable()) {
                if ($this->dialect === 'postgres') {
                    $expr = [];
                    foreach ($this->searchable() as $c) {
                        if ($c === '' || !isset($allowedFilter[$c])) continue;
                        $expr[] = "coalesce(" . $this->refCol($c, $viewMode) . ", '')";
                    }
                    if ($expr) {
                        $k = $this->uniqueParam(':ft_q_');
                        $params[$k] = $this->search;
                        $dict = $this->quote($this->fulltextDict);
                        $where[] = "( to_tsvector({$dict}, " . \implode(" || ' ' || ", $expr) . ") @@ plainto_tsquery({$dict}, $k) )";
                    }
                } else { // mysql/mariadb
                    $cols = [];
                    foreach ($this->searchable() as $c) {
                        if ($c === '' || !isset($allowedFilter[$c])) continue;
                        $cols[] = $this->refCol($c, $viewMode);
                    }
                    if ($cols) {
                        $k = $this->uniqueParam(':ft_q_');
                        $params[$k] = $this->search;
                        $where[] = "( MATCH(" . \implode(',', $cols) . ") AGAINST ($k IN NATURAL LANGUAGE MODE) )";
                    }
                }
            } else {
                $likeParts = []; $i=0;
                foreach ($this->searchable() as $c) {
                    if ($c === '' || !isset($allowedFilter[$c])) continue;
                    $k = $this->paramKey("s", $c, $i++);
                    $val = '%' . Search::escapeLike($this->search) . '%';
                    $params[$k] = $val;
                    $op = ($this->dialect === 'postgres' && $this->caseInsensitiveLike) ? 'ILIKE' : 'LIKE';
                    $likeParts[] = $this->refCol($c, $viewMode) . " $op $k" . Search::escClause($this->dialect);
                }
                if ($likeParts) { $where[] = '(' . \implode(' OR ', $likeParts) . ')'; }
            }
        }

        // Raw additions (each inserted with its own parameters)
        foreach ($this->raw as $r) {
            $where[] = '(' . $r['sql'] . ')';
            foreach ($r['params'] as $k => $v) { $params[$k] = $v; }
        }

        if (!$where) { $where = ['1=1']; }

        // ORDER
        $order = null;
        if ($this->seekPk !== null && ($this->isAllowedSort($this->seekPk, $allowedSort) || isset($allowedFilter[$this->seekPk]))) {
            $order = $this->buildOrderPiece($this->seekPk, $this->seekDir, false, $viewMode);
        } elseif ($this->sort) {
            $parts = [];
            foreach ($this->sort as $s) {
                [$c,$d,$nl] = [$s['col'], \strtoupper($s['dir'] ?? 'ASC'), (bool)$s['nullsLast']];
                if (!isset($allowedSort[$c])) { continue; }
                $parts[] = $this->buildOrderPiece($c, $d, $nl, $viewMode);
            }
            if ($parts) { $order = \implode(', ', $parts); }
        }

        // LIMIT/OFFSET
        $limit  = $this->explicitLimit  ?? $this->perPage;
        $offset = $this->explicitOffset ?? (($this->page - 1) * $this->perPage);

        // SEEK filtr
        if ($this->seekPk !== null && ($this->isAllowedSort($this->seekPk, $allowedSort) || isset($allowedFilter[$this->seekPk]))) {
            $cmp = $this->seekInclusive
                ? ($this->seekDir === 'ASC' ? '>=' : '<=')
                : ($this->seekDir === 'ASC' ? '>'  : '<' );
            $k = $this->paramKey("seek", $this->seekPk, 0);
            $params[$k] = $this->seekAfter;
            $where[] = $this->refCol($this->seekPk, $viewMode) . " $cmp $k";
            $offset = 0; // offset does not make sense when using seek
        }

        // JOINy + parametry
        $joins = $this->joins ? \implode(' ', $this->joins) : '';
        if ($this->joinParams) { $params = $this->joinParams + $params; }
        if ($this->extraParams) { $params = $this->extraParams + $params; }

        return [\implode(' AND ', $where), $params, $order, $limit, $offset, $joins];
    }

    /* -------------------- Helpery -------------------- */

    private function quote(string $s): string
    {
        return "'" . \str_replace("'", "''", $s) . "'";
    }

    private function uniqueParam(string $prefix = ':p_'): string
    {
        // Guaranteed unique key; e.g. :json_contains_1
        return $prefix . (++$this->paramSeq);
    }

    private function paramKey(string $a, string $b, int $i): string
    {
        $norm = static fn(string $x) => (string)\preg_replace('~[^A-Za-z0-9_]+~', '_', $x);
        return ':' . $norm($a) . '_' . $norm($b) . '_' . $i . '_' . (++$this->paramSeq);
    }

    private function buildOrderPiece(string $col, string $dir, bool $nullsLast, bool $viewMode): string
    {
        $dir = \in_array($dir, ['ASC','DESC'], true) ? $dir : 'ASC';
        $refCol = $this->refCol($col, $viewMode);
        if (!$nullsLast) return "$refCol $dir";
        if ($this->dialect === 'postgres') {
            return "$refCol $dir NULLS LAST";
        }
        return "($refCol IS NULL), $refCol $dir";
    }

    // Safe column reference (respects "t." prefix in viewMode + optional identifier quoting)
    private function refCol(string $col, bool $viewMode): string
    {
        if ($col === '') return $col;
        if (\strpos($col, '.') !== false) {
            [$a,$b] = \explode('.', $col, 2);
            return $this->quoteIdent($a) . '.' . $this->quoteIdent($b);
        }
        return $viewMode
            ? ($this->quoteIdent('t') . '.' . $this->quoteIdent($col))
            : ($this->quoteIdentifiers ? $this->quoteIdent($col) : $col);
    }

    private function quoteIdent(string $name): string
    {
        if (!$this->quoteIdentifiers) return $name;
        // Prefer driver-aware quoting when Database is available
        if ($this->db instanceof Database) {
            try { return $this->db->quoteIdent($name); } catch (\Throwable) { /* fallback below */ }
        }
        if ($this->dialect === 'postgres') {
            return '"' . \str_replace('"','""',$name) . '"';
        }
        return '`' . \str_replace('`','``',$name) . '`';
    }

    /** Checks whether a column is allowed for sort/seek. */
    private function isAllowedSort(string $col, array $allowedSort): bool
    {
        return isset($allowedSort[$col]);
    }

    public function softDelete(string $column = 'deleted_at'): self
    {
        $this->softDeleteCol = $column;
        return $this;
    }

    public function withTrashed(bool $on = true): self
    {
        $this->withTrashed = $on;
        if ($on) $this->onlyTrashed = false;
        return $this;
    }

    public function onlyTrashed(bool $on = true): self
    {
        $this->onlyTrashed = $on;
        if ($on) $this->withTrashed = false;
        return $this;
    }
}
