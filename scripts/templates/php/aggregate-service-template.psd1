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
 * Orchestruje více repozitářů v jedné transakci (s podporou savepointů).
 * - Idempotence/locking nechává na Repository/DB vrstvě.
 * - Má helpery: runInTransaction(), retryOnDeadlock(), withLock().
 */
final class [[SERVICE_CLASS]]
{
    public function __construct(
        [[CTOR_PARAMS]]
    ) {}

    /**
     * Spusť v transakci. Preferuje Database::transaction(callable): mixed.
     * Fallback: begin/commit/rollback, případně savepointy pokud už transakce běží.
     */
    private function runInTransaction(callable $fn): mixed
    {
        if (method_exists($this->db, 'transaction')) {
            return $this->db->transaction($fn);
        }

        $hasTxApi = method_exists($this->db, 'beginTransaction')
            && method_exists($this->db, 'commit')
            && method_exists($this->db, 'rollBack');

        $hasExec = method_exists($this->db, 'exec');
        $inTx    = method_exists($this->db, 'inTransaction') ? (bool)$this->db->inTransaction() : false;

        if ($hasTxApi) {
            if ($inTx && $hasExec) {
                // savepoint branch
                $sp = '__svc_' . bin2hex(random_bytes(4));
                $this->db->exec('SAVEPOINT ' . $sp);
                try {
                    $res = $fn($this->db);
                    $this->db->exec('RELEASE SAVEPOINT ' . $sp);
                    return $res;
                } catch (\Throwable $e) {
                    $this->db->exec('ROLLBACK TO SAVEPOINT ' . $sp);
                    throw $e;
                }
            }

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

        // nouzový běh bez transakce (např. v test double)
        return $fn($this->db);
    }

    /**
     * Opakuj blok při deadlocku / serialization failure (exponenciální backoff).
     * Detekuje PG SQLSTATE 40001/40P01 a MySQL kódy 1205/1213.
     */
    private function retryOnDeadlock(callable $fn, int $maxAttempts = 3): mixed
    {
        $attempt = 0;
        do {
            try {
                return $fn();
            } catch (\Throwable $e) {
                $attempt++;
                $sig   = strtolower($e->getMessage());
                $state = ($e instanceof \PDOException) ? (string)($e->errorInfo[0] ?? '') : '';
                $code  = ($e instanceof \PDOException) ? (int)($e->errorInfo[1] ?? 0) : 0;

                $isPgDeadlock  = in_array($state, ['40001','40p01'], true);
                $isMyDeadlock  = in_array($code, [1205,1213], true);
                $looksDeadlock = $isPgDeadlock || $isMyDeadlock
                    || str_contains($sig, 'deadlock') || str_contains($sig, 'serialization');

                if (!$looksDeadlock || $attempt >= $maxAttempts) {
                    throw $e;
                }

                // backoff
                usleep((int)(100000 * (2 ** ($attempt - 1)))); // 0.1s, 0.2s, 0.4s
            }
        } while (true);
    }

    /**
     * Zamkni řádek (FOR UPDATE) a proveď práci uvnitř téže transakce.
     * $fetch je callable(array $row, Database $db): mixed
     */
    protected function withLock(callable $locker, int|string $id, callable $fetch): mixed
    {
        return $this->runInTransaction(function () use ($locker, $id, $fetch) {
            $row = $locker($id); // očekává se $repo->lockById($id)
            if (!$row) {
                throw new \[[NAMESPACE]]\ModuleException("Záznam $id nenalezen pro zámek.");
            }
            return $fetch($row, $this->db);
        });
    }

[[AGGREGATE_METHODS]]
}
'@
}
