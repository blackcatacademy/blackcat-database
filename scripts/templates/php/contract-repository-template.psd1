@{
  File   = 'src/ContractRepository.php'
  Tokens = @('NAMESPACE')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

interface ContractRepository
{
    public function insert(array $row): void;
    public function insertMany(array $rows): void;
    public function upsert(array $row): void;

    public function updateById(int|string $id, array $row): int;
    public function deleteById(int|string $id): int;
    public function restoreById(int|string $id): int;

    public function findById(int|string $id): ?array;
    public function exists(string $whereSql = '1=1', array $params = []): bool;
    public function count(string $whereSql = '1=1', array $params = []): int;

    public function paginate(Criteria $c): array;
    public function lockById(int|string $id): ?array;
}
'@
}
