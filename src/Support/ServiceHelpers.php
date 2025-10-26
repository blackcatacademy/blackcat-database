<?php
declare(strict_types=1);

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;
use BlackCat\Core\Database\QueryCache;
use Psr\Log\LoggerInterface;

trait ServiceHelpers
{
    /** OČEKÁVÁ se, že třída má property: private Database $db; (a volitelně private ?QueryCache $qcache) */

    protected function db(): Database {
        if (property_exists($this, 'db') && $this->db instanceof Database) {
            return $this->db;
        }
        if (method_exists($this, 'getDb')) {
            $db = $this->getDb();
            if ($db instanceof Database) return $db;
        }
        throw new \LogicException('Service is missing Database dependency.');
    }
    protected function qcache(): ?QueryCache { /** @var ?QueryCache $qcache */ return $this->qcache ?? null; }

    /** Transakce (R/W) */
    protected function txn(callable $fn): mixed { return $this->db()->transaction(fn()=> $fn($this)); }

    /** Read-only transakce (PG nativně, MySQL korektní fallback) */
    protected function txnRO(callable $fn): mixed { return $this->db()->transactionReadOnly(fn()=> $fn($this)); }

    /** Advisory lock – scope-limited */
    protected function withLock(string $name, int $timeoutSec, callable $fn): mixed {
        return $this->db()->withAdvisoryLock($name, $timeoutSec, fn()=> $fn($this));
    }

    /** Statement timeout na scope */
    protected function withTimeout(int $ms, callable $fn): mixed {
        return $this->db()->withStatementTimeout($ms, fn()=> $fn($this));
    }

    /** Retry transientních chyb (deadlocky, serialization) */
    protected function retry(int $attempts, callable $fn): mixed {
        $try = 0; $delay = 50;
        while (true) {
            try { return $fn($this); }
            catch (\PDOException $e) {
                $try++;
                // využijeme privátní heuristiku DB executeWithRetry přes jednoduchý wrapper:
                if ($try >= $attempts) throw $e;
                usleep($delay*1000); $delay = min($delay*2, 1000);
            }
        }
    }

    /** Keyset stránkování */
    protected function keyset(string $sqlBase, array $params, string $pkCol, ?string $after, int $limit=50): array {
        return $this->db()->paginateKeyset($sqlBase, $params, $pkCol, $after, $limit);
    }

    /** EXPLAIN / ANALYZE (PG) */
    protected function explain(string $sql, array $params=[], bool $analyze=false): array {
        return $this->db()->explainPlan($sql, $params, $analyze);
    }

    /** Cache-wrapper pro SELECTy (pokud je k dispozici QueryCache) */
    protected function cacheRows(string $sql, array $params, int $ttlSec): array {
        $qc = $this->qcache();
        if (!$qc) return $this->db()->fetchAll($sql, $params);
        return $qc->rememberRows($this->db(), $sql, $params, $ttlSec);
    }

    /** Utility: identifikátory a kvóty */
    protected function idKey(string $ns, string $id): string {
        $dbId = 'db';
        try {
            $db = $this->db();
            if ($db && method_exists($db, 'id')) { $dbId = (string)$db->id(); }
        } catch (\Throwable $_) {}
        return $ns . ':' . $dbId . ':' . $id;
    }
}

/*Do vygenerovaných Service tříd stačí přidat use BlackCat\Database\Support\ServiceHelpers; a trait použít:
final class UsersAggregateService { use ServiceHelpers; public function __construct(private Database $db,  ...  private ?QueryCache $qcache = null) {} }*/