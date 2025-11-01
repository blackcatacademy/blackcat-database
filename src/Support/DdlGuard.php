<?php
declare(strict_types=1);

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Exceptions\DdlRetryExceededException;
use BlackCat\Database\Exceptions\ViewVerificationException;
use Psr\Log\LoggerInterface;

/**
 * Samostatná vrstva pro robustní CREATE VIEW (MySQL) + verifikaci direktiv.
 * Nepoužívá žádné privátní API z Core\Database – jen veřejné metody.
 */
final class DdlGuard
{
    public function __construct(
        private Database $db,
        private SqlDialect $dialect,
        private ?LoggerInterface $logger = null
    ) {
        $this->logger = $this->logger ?? $db->getLogger();
    }

    /** Quote identifikátoru včetně schema.view přes Database::quoteIdent(). */
    private function qi(string $ident): string
    {
        $parts = explode('.', $ident);
        return implode('.', array_map(fn($p) => $this->db->quoteIdent($p), $parts));
    }

    /**
     * Aplikuje jeden CREATE VIEW statement robustně:
     * - per-view advisory lock
     * - volitelný DROP FIRST
     * - CREATE (preferencí bez OR REPLACE)
     * - fence (SHOW CREATE VIEW + SELECT * FROM view LIMIT 0)
     * - verifikace ALGORITHM/SECURITY; při driftu force-recreate s retry
     */
    public function applyCreateView(string $stmt, array $opts = []): void
    {
        [$name, $expectAlg, $expectSec] = $this->parseCreateViewHead($stmt);

        $lockTimeout   = (int)($opts['lockTimeoutSec'] ?? 10);
        $retries       = max(1, (int)($opts['retries'] ?? (int)(getenv('BC_INSTALLER_VIEW_RETRIES') ?: 3)));
        $fenceMs       = (int)($opts['fenceMs'] ?? (int)(getenv('BC_VIEW_FENCE_MS') ?: 600));
        $dropFirst     = (bool)($opts['dropFirst'] ?? true);
        $normalizeOR   = (bool)($opts['normalizeOrReplace'] ?? true);

        // Pro MySQL preferujeme čisté CREATE, když děláme drop-first
        $create = $stmt;
        if ($normalizeOR) {
            $create = preg_replace('~\bCREATE\s+OR\s+REPLACE\b~i', 'CREATE', $create);
        }

        $this->db->withAdvisoryLock('view:'.$name, $lockTimeout, function() use ($name, $dropFirst, $create, $retries, $fenceMs, $expectAlg, $expectSec) {
            // 1) DROP (best-effort) – tím se vyhneme podivnostem OR REPLACE
            if ($dropFirst) {
                try { $this->db->exec('DROP VIEW IF EXISTS '.$this->qi($name)); }
                catch (\Throwable $e) { $this->log('warning', 'DROP VIEW failed (ignoring)', ['view'=>$name,'err'=>$e->getMessage()]); }
            }

            // 2) CREATE + fence + verify (+ případný force recreate), s retry
            $attempt = 0;
            $lastErr = null;
            while ($attempt < $retries) {
                $attempt++;
                try {
                    $this->db->exec($create);
                    $this->fenceViewReady($name, $fenceMs);

                    if ($this->dialect->isMysql()) {
                        $got = $this->currentMySqlDirectives($name);
                        $okAlg = !$expectAlg || strtoupper((string)$got['algorithm']) === strtoupper($expectAlg);
                        $okSec = !$expectSec || strtoupper((string)$got['security'])  === strtoupper($expectSec);

                        if ($okAlg && $okSec) {
                            return; // hotovo
                        }

                        // Force recreate (bez OR REPLACE)
                        $this->log('warning', 'View drift detected; recreating', ['view'=>$name,'expect'=>[$expectAlg,$expectSec],'got'=>$got,'attempt'=>$attempt]);

                        try { $this->db->exec('DROP VIEW IF EXISTS '.$this->qi($name)); } catch (\Throwable $_) {}
                        $this->db->exec($create);
                        $this->fenceViewReady($name, $fenceMs);

                        $got2 = $this->currentMySqlDirectives($name);
                        $okAlg = !$expectAlg || strtoupper((string)$got2['algorithm']) === strtoupper($expectAlg);
                        $okSec = !$expectSec || strtoupper((string)$got2['security'])  === strtoupper($expectSec);
                        if ($okAlg && $okSec) return;
                        $lastErr = ViewVerificationException::drift($name, $got2, ['algorithm'=>$expectAlg,'security'=>$expectSec]);
                        // padáme do retry smyčky
                    } else {
                        // PG: nemáme direktivy, CREATE stačí
                        return;
                    }
                } catch (\PDOException $e) {
                    // transient? necháme další pokus (drop/create bývá rychlá operace)
                    $lastErr = $e;
                    usleep(min(1000, 40 * (1 << ($attempt - 1))) * 1000); // exponenciální backoff 40,80,160,… ms
                }
            }
            // po vyčerpání
            throw new DdlRetryExceededException("CREATE VIEW {$name}", $retries, $lastErr);
        });
    }

    /** Čeká, než je view skutečně dostupné pro parser i metadata. (MySQL only) */
    public function fenceViewReady(string $name, int $maxWaitMs = 600): void
    {
        if (!$this->dialect->isMysql()) return;
        $deadline = microtime(true) + ($maxWaitMs / 1000.0);
        do {
            $ddl = $this->showCreateView($name);
            if ($ddl !== null) {
                try {
                    $this->db->withStatement('SELECT * FROM '.$this->qi($name).' LIMIT 0', fn($s)=>true);
                    return;
                } catch (\Throwable) {}
            }
            usleep(30 * 1000);
        } while (microtime(true) < $deadline);

        $this->log('warning', 'fenceViewReady timeout', ['view'=>$name,'wait_ms'=>$maxWaitMs]);
    }

    /** Vyparsuje z CREATE VIEW název + očekávané direktivy. */
    private function parseCreateViewHead(string $stmt): array
    {
        $name = null; $alg = null; $sec = null;

        if (!preg_match('~\bVIEW\s+([`"]?[A-Za-z0-9_]+[`"]?(?:\.[`"]?[A-Za-z0-9_]+[`"]?)?)\s+AS~i', $stmt, $m)) {
            throw new \InvalidArgumentException('Cannot parse VIEW name from statement head='.substr(trim($stmt),0,120));
        }
        $name = preg_replace('~[`"]~', '', $m[1]); // strip quote znaků, ponech tečku

        if (preg_match('~\bALGORITHM\s*=\s*(UNDEFINED|MERGE|TEMPTABLE)\b~i', $stmt, $mm)) {
            $alg = strtoupper($mm[1]);
        }
        if (preg_match('~\bSQL\s+SECURITY\s+(DEFINER|INVOKER)\b~i', $stmt, $mm)) {
            $sec = strtoupper($mm[1]);
        }
        return [$name, $alg, $sec];
    }

    /** SHOW CREATE VIEW → parse ALGORITHM/SECURITY/DEFINER (MySQL only) */
    private function currentMySqlDirectives(string $name): array
    {
        $ddl = $this->showCreateView($name);
        $out = ['algorithm'=>null,'security'=>null,'definer'=>null];
        if ($ddl === null) return $out;

        if (preg_match('~\bALGORITHM\s*=\s*(UNDEFINED|MERGE|TEMPTABLE)\b~i', $ddl, $m)) {
            $out['algorithm'] = strtoupper($m[1]);
        }
        if (preg_match('~\bSQL\s+SECURITY\s+(DEFINER|INVOKER)\b~i', $ddl, $m)) {
            $out['security'] = strtoupper($m[1]);
        }
        if (preg_match('~\bDEFINER\s*=\s*([^ ]+)~i', $ddl, $m)) {
            $out['definer'] = $m[1];
        }
        return $out;
    }

    private function showCreateView(string $name): ?string
    {
        if (!$this->dialect->isMysql()) return null;
        try {
            $row = $this->db->fetch('SHOW CREATE VIEW '.$this->qi($name)) ?? [];
            return (string)($row['Create View'] ?? (array_values($row)[1] ?? ''));
        } catch (\Throwable) {
            return null;
        }
    }

    private function log(string $level, string $msg, array $ctx = []): void
    {
        if ($this->logger) { $this->logger->log($level, '[DdlGuard] '.$msg, $ctx); return; }
        error_log('[DdlGuard]['.strtoupper($level).'] '.$msg.' '.json_encode($ctx));
    }
}
