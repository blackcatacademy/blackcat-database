@{
  File   = 'src/Service/[[SERVICE_CLASS]].php'
  Tokens = @(
    'NAMESPACE',        # např. BlackCat\Database\Packages\Orders
    'SERVICE_CLASS',    # např. OrdersAggregateService
    'USES_ARRAY',       # pole plných use, např. ["use BlackCat\Core\Database;","use BlackCat\Database\Packages\Orders\Repository as OrdersRepo;"]
    'CTOR_PARAMS',      # např. "private Database $db, private OrdersRepo $orders, private OrderItemsRepo $orderItems"
    'AGGREGATE_METHODS' # vygenerované/kostra metod – může zůstat prázdné
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Service;

[[USES_ARRAY]]

/**
 * Orchestruje více repozitářů v **jedné transakci**.
 * - Idempotentní vzory (zámky, verze) nechává na vrstvě Repository/DB.
 * - Zde řešíme business workflow přes hranice tabulek.
 */
final class [[SERVICE_CLASS]]
{
    public function __construct(
        [[CTOR_PARAMS]]
    ) {}

    /**
     * Vykoná akci v transakci – adaptuje se na dostupné API DB wrapperu.
     * Předpoklad:
     *   - pokud existuje Database::transaction(callable): mixed, použijeme jej
     *   - jinak fallback begin/commit/rollback
     */
    private function runInTransaction(callable $fn): mixed {
        if (method_exists($this->db, 'transaction')) {
            return $this->db->transaction($fn);
        }
        if (method_exists($this->db, 'beginTransaction')
            && method_exists($this->db, 'commit')
            && method_exists($this->db, 'rollBack')) {
            $this->db->beginTransaction();
            try {
                $res = $fn($this->db);
                $this->db->commit();
                return $res;
            } catch (\Throwable $e) {
                $this->db->rollBack();
                throw $e;
            }
        }
        // nouzově (neatomické) – ale aspoň nezabrání běhu v testech
        return $fn($this->db);
    }

[[AGGREGATE_METHODS]]
}
'@
}
