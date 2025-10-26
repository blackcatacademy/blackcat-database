<?php
declare(strict_types=1);

namespace Tests\Fakes;

final class InMemoryRepo
{
    /** @var array<int|string,array> */
    public array $rows = [];
    public int|string $nextId = 1;
    public string $pk = 'id';
    public ?string $versionCol = null;

    // metriky/diagnostika
    public int $hitsFindById = 0;
    public int $callsInsert = 0;
    public int $callsInsertMany = 0;
    public int $callsUpsert = 0;
    public int $callsUpdate = 0;

    // volitelná „výbava“ repozitáře
    public bool $exposeUpsert = true;
    public bool $exposeExists = true;
    public bool $exposeLockById = true;
    public bool $exposeInsertMany = true;

    // Retry simulace
    public int $throwDeadlocksTimes = 0; // kolikrát má update vyhodit „deadlock“

    public function __construct(string $pk = 'id', ?string $versionCol = null)
    {
        $this->pk = $pk;
        $this->versionCol = $versionCol;
    }

    // ---------- CRUD ----------

    public function insert(array $row): void
    {
        $this->callsInsert++;
        if (!array_key_exists($this->pk, $row) || $row[$this->pk] === null || $row[$this->pk] === '') {
            $row[$this->pk] = $this->nextId++;
        }
        if ($this->versionCol && !array_key_exists($this->versionCol, $row)) {
            $row[$this->versionCol] = 0;
        }
        $this->rows[$row[$this->pk]] = $row;
    }

    public function insertMany(array $rows): void
    {
        if (!$this->exposeInsertMany) {
            throw new \BadMethodCallException('insertMany not exposed');
        }
        $this->callsInsertMany++;
        foreach ($rows as $r) { $this->insert($r); }
    }

    public function upsert(array $row): void
    {
        if (!$this->exposeUpsert) {
            throw new \BadMethodCallException('upsert not exposed');
        }
        $this->callsUpsert++;
        $id = $row[$this->pk] ?? null;
        if ($id !== null && isset($this->rows[$id])) {
            $upd = $row; unset($upd[$this->pk]);
            $this->updateById($id, $upd);
        } else {
            $this->insert($row);
        }
    }

    public function updateById(int|string $id, array $row): int
    {
        $this->callsUpdate++;
        // simulace deadlocku pro retry test
        if ($this->throwDeadlocksTimes > 0) {
            $this->throwDeadlocksTimes--;
            $e = new \PDOException('deadlock', 0);
            // PG 40001 nebo MySQL 1213 – stačí jedno
            $e->errorInfo = ['40001', 1213, 'deadlock'];
            throw $e;
        }

        if (!isset($this->rows[$id])) return 0;

        // optimistic locking
        if ($this->versionCol && array_key_exists($this->versionCol, $row)) {
            $expected = (int)$row[$this->versionCol];
            $current  = (int)($this->rows[$id][$this->versionCol] ?? 0);
            if ($expected !== $current) {
                return 0; // konflikt verze
            }
            unset($row[$this->versionCol]);
            $this->rows[$id][$this->versionCol] = $current + 1;
        }

        foreach ($row as $k => $v) {
            if ($k === $this->pk) continue;
            $this->rows[$id][$k] = $v;
        }
        return 1;
    }

    public function deleteById(int|string $id): int
    {
        if (!isset($this->rows[$id])) return 0;
        unset($this->rows[$id]);
        return 1;
    }

    public function restoreById(int|string $id): int
    {
        // jednoduchý fake: nemáme soft-delete → 0
        return 0;
    }

    public function findById(int|string $id): ?array
    {
        $this->hitsFindById++;
        return $this->rows[$id] ?? null;
    }

    public function exists(string $whereSql = '1=1', array $params = []): bool
    {
        if (!$this->exposeExists) {
            throw new \BadMethodCallException('exists not exposed');
        }
        // Podpora nejběžnějšího tvaru „id = :id“
        if (preg_match('~\bid\s*=\s*:id\b~i', $whereSql) && isset($params[':id'])) {
            return isset($this->rows[$params[':id']]);
        }
        // fallback: cokoliv → existuje aspoň jeden řádek
        return !empty($this->rows);
    }

    public function count(string $_where = '1=1', array $_params = []): int
    {
        return \count($this->rows);
    }

    public function paginate(object $criteria): array
    {
        $items = \array_values($this->rows);
        return ['items' => $items, 'total' => \count($items), 'page' => 1, 'perPage' => \count($items)];
    }

    public function lockById(int|string $id): ?array
    {
        if (!$this->exposeLockById) {
            throw new \BadMethodCallException('lockById not exposed');
        }
        // žádný reálný zámek; jen vrátíme řádek
        return $this->findById($id);
    }
}
