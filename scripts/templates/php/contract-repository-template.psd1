@{
  File   = 'src/ContractRepository.php'
  Tokens = @('NAMESPACE','VIEW')
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

use BlackCat\Core\Database\Database;

final class ContractRepository {
    public function __construct(private Database $db) {}

    public function findOne(string $where, array $params): ?array {
        $sql = "SELECT * FROM [[VIEW]] WHERE $where LIMIT 1";
        return $this->db->fetchOne($sql, $params) ?: null;
    }

    public function list(string $where = "1=1", array $params = [], ?string $order = null, ?int $limit = null, ?int $offset = null): array {
        $order  = $order  ?: '1';
        $suffix = '';
        if ($limit !== null)  { $suffix .= " LIMIT ".(int)$limit; }
        if ($offset !== null) { $suffix .= " OFFSET ".(int)$offset; }
        $sql = "SELECT * FROM [[VIEW]] WHERE $where ORDER BY $order".$suffix;
        return $this->db->fetchAll($sql, $params);
    }

    /** Stránkování přes Criteria (používá sloupce view) */
    public function paginateView(Criteria $c): array {
        [$where, $params, $order, $limit, $offset, $joins] = $c->toSql(viewMode: true);
        $order = $order ?: '1';
        $joins = $joins ?: '';
        $total = (int)$this->db->fetchOne("SELECT COUNT(*) FROM [[VIEW]] v $joins WHERE $where", $params);
        $items = $this->db->fetchAll("SELECT v.* FROM [[VIEW]] v $joins WHERE $where ORDER BY $order LIMIT $limit OFFSET $offset", $params);
        return ['items'=>$items,'total'=>$total,'page'=>$c->page(),'perPage'=>$c->perPage()];
    }
}
'@
}
