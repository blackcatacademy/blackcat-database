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

namespace BlackCat\Database\ReadReplica;

use BlackCat\Core\Database;
use BlackCat\Database\Support\Observability;

/**
 * Read-replica Router
 *
 * Safely routes SQL to primary/replica with a "sticky" window after writes.
 * - Detects write/maintenance/transaction statements and always targets **primary**.
 * - Detects SELECT with **FOR UPDATE/SHARE/.../SKIP LOCKED** → **primary** (read_lock).
 * - After write/read_lock it marks the correlation ID as **sticky** for a short window so follow-up
 *   reads still hit primary (masking replication lag).
 * - If a transaction is active on primary, **everything** goes to primary.
 *
 * Developer-friendly API: forwarders `exec/fetch/exists` propagate meta (corr/op...).
 */
final class Router
{
    /** @var array<string,float> corr => expiresAtMs (monotonic ms) */
    private array $sticky = [];
    private int $stickyGcEvery = 1024;
    private int $stickyOps = 0;
    private int $stickyMaxSize = 4096;

    public function __construct(
        private Database $primary,
        private ?Database $replica = null,
        private int $stickyMs = 1500 // short window to shield replication lag
    ) {}

    public function primary(): Database { return $this->primary; }
    public function replica(): ?Database { return $this->replica; }

    /** Marks a correlation ID as sticky after a write / write-like SELECT so subsequent reads use primary briefly. */
    public function markSticky(?string $corr, ?int $ms = null): void
    {
        if ($corr === null || $corr === '') return;
        $win = $ms !== null ? max(0, $ms) : max(0, $this->stickyMs);
        if ($win <= 0) { unset($this->sticky[$corr]); return; }
        $this->sticky[$corr] = $this->nowMs() + $win;
        $this->gcStickyIfNeeded();
    }

    private function isSticky(?string $corr): bool
    {
        if ($corr === null || $corr === '') return false;
        $exp = $this->sticky[$corr] ?? 0.0;
        if ($exp <= $this->nowMs()) { unset($this->sticky[$corr]); return false; }
        return true;
    }

    /**
     * Picks a database based on SQL and meta (sticky after write/lock; transactions → primary).
     *
     * @param array<string,mixed> $meta
     */
    public function pick(string $sql, array $meta = []): Database
    {
        $meta = Observability::ensureCorr($meta);

        // 0) No replica available → always primary
        if ($this->replica === null) {
            return $this->primary;
        }

        // 1) An active transaction on primary means everything stays on primary
        if ($this->primary->inTransaction()) {
            return $this->primary;
        }

        // 2) Sticky window after write/lock
        if ($this->isSticky($meta['corr'] ?? null)) {
            return $this->primary;
        }

        // 3) Decide based on query nature
        $kind = $this->classify($sql);
        if ($kind === 'read') {
            return $this->replica;
        }
        return $this->primary;
    }

    /** Force primary (e.g. when requested by upper layers). */
    public function pickForWrite(): Database { return $this->primary; }

    // ---- Forwarders s meta --------------------------------------------------

    /** @param array<string,mixed> $params @param array<string,mixed> $meta */
    public function execWithMeta(string $sql, array $params = [], array $meta = []): int
    {
        $meta = Observability::ensureCorr($meta);
        $class = $this->classify($sql);
        $db    = $this->pick($sql, $meta);
        $n     = $db->execWithMeta($sql, $params, $meta);
        // Mark sticky after write/read_lock so subsequent reads briefly hit primary
        if ($class !== 'read') {
            $this->markSticky($meta['corr'] ?? null);
        }
        return $n;
    }

    /** @param array<string,mixed> $params @param array<string,mixed> $meta */
    public function fetchRowWithMeta(string $sql, array $params = [], array $meta = []): ?array
    {
        $meta = Observability::ensureCorr($meta);
        $class = $this->classify($sql);
        $db    = $this->pick($sql, $meta);
        $row   = $db->fetchRowWithMeta($sql, $params, $meta);
        if ($class === 'read_lock') {
            $this->markSticky($meta['corr'] ?? null);
        }
        return $row;
    }

    /** @param array<string,mixed> $params @param array<string,mixed> $meta */
    public function fetchAllWithMeta(string $sql, array $params = [], array $meta = []): array
    {
        $meta = Observability::ensureCorr($meta);
        $class = $this->classify($sql);
        $db    = $this->pick($sql, $meta);
        $rows  = $db->fetchAllWithMeta($sql, $params, $meta);
        if ($class === 'read_lock') {
            $this->markSticky($meta['corr'] ?? null);
        }
        return $rows;
    }

    /** @param array<string,mixed> $params @param array<string,mixed> $meta */
    public function fetchValueWithMeta(string $sql, array $params = [], mixed $default = null, array $meta = []): mixed
    {
        $meta = Observability::ensureCorr($meta);
        $class = $this->classify($sql);
        $db    = $this->pick($sql, $meta);
        $val   = $db->fetchValueWithMeta($sql, $params, $default, $meta);
        if ($class === 'read_lock') {
            $this->markSticky($meta['corr'] ?? null);
        }
        return $val;
    }

    /** @param array<string,mixed> $params @param array<string,mixed> $meta */
    public function existsWithMeta(string $sql, array $params = [], array $meta = []): bool
    {
        $meta = Observability::ensureCorr($meta);
        $class = $this->classify($sql);
        $db    = $this->pick($sql, $meta);
        $ok    = $db->existsWithMeta($sql, $params, $meta);
        if ($class === 'read_lock') {
            $this->markSticky($meta['corr'] ?? null);
        }
        return $ok;
    }

    // ---- Helper functions --------------------------------------------------

    /** Monotonic time in ms (hrtime). */
    private function nowMs(): float
    {
        return \hrtime(true) / 1_000_000.0;
    }

    /** Lightweight GC for the sticky map when it grows. */
    private function gcStickyIfNeeded(): void
    {
        if ((++$this->stickyOps % $this->stickyGcEvery) !== 0) return;
        if (\count($this->sticky) <= $this->stickyMaxSize) return;

        $now = $this->nowMs();
        foreach ($this->sticky as $k => $exp) {
            if ($exp <= $now) unset($this->sticky[$k]);
        }
        if (\count($this->sticky) > $this->stickyMaxSize) {
            \asort($this->sticky); // prioritise earliest expirations
            $cut = \count($this->sticky) - $this->stickyMaxSize;
            foreach (\array_keys($this->sticky) as $k) {
                unset($this->sticky[$k]);
                if (--$cut <= 0) break;
            }
        }
    }

    /** Strips leading comments and whitespace. */
    private function stripLead(string $sql): string
    {
        $s = \ltrim($sql);

        // Multiple consecutive comments
        while (true) {
            if (\str_starts_with($s, '/*')) {
                $s = (string)\preg_replace('~/\*.*?\*/~s', '', $s, 1);
                $s = \ltrim($s);
                continue;
            }
            if (\str_starts_with($s, '--')) {
                $s = (string)\preg_replace('~^--.*?$~m', '', $s, 1);
                $s = \ltrim($s);
                continue;
            }
            break;
        }
        return $s;
    }

    /**
     * Rough classifier: 'read' | 'read_lock' | 'write'
     * - Distinguishes SELECT statements with FOR UPDATE/SHARE/NO KEY UPDATE/KEY SHARE and SKIP LOCKED.
     * - Detects CTE, multi-statement, transaction, and DDL/maintenance commands.
     */
    private function classify(string $sql): string
    {
        $s = $this->stripLead($sql);

        // Multi-statement or CALL/DO → treat as write
        if (\str_contains($s, ';') || \preg_match('~^\s*(CALL|DO)\b~i', $s)) {
            return 'write';
        }

        // Transaction / session / lock statements → write
        if (\preg_match('~^\s*(BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET\s+|LOCK\s+|UNLOCK\s+)~i', $s)) {
            return 'write';
        }

        // DDL and maintenance → write
        if (\preg_match('~^\s*(CREATE|ALTER|DROP|TRUNCATE|REINDEX|VACUUM|ANALYZE|REFRESH\s+MATERIALIZED|CLUSTER)\b~i', $s)) {
            return 'write';
        }

        // CTE – treat heuristically as SELECT but still detect FOR UPDATE/SHARE
        if (\preg_match('~^\s*WITH\b~i', $s)) {
            if (\preg_match('~\bFOR\s+(UPDATE|SHARE|NO\s+KEY\s+UPDATE|KEY\s+SHARE)\b~i', $s) ||
                \preg_match('~\bSKIP\s+LOCKED\b~i', $s)) {
                return 'read_lock';
            }
            return 'read';
        }

        // SELECT … (including variants with FOR UPDATE/SHARE, etc.)
        if (\preg_match('~^\s*SELECT\b~i', $s)) {
            // MySQL SELECT … INTO OUTFILE/DUMPFILE is considered write-like
            if (\preg_match('~\bINTO\s+(OUTFILE|DUMPFILE)\b~i', $s)) {
                return 'write';
            }
            if (\preg_match('~\bFOR\s+(UPDATE|SHARE|NO\s+KEY\s+UPDATE|KEY\s+SHARE)\b~i', $s) ||
                \preg_match('~\bSKIP\s+LOCKED\b~i', $s)) {
                return 'read_lock';
            }
            return 'read';
        }

        // "Harmless" read
        if (\preg_match('~^\s*(SHOW|EXPLAIN|DESCRIBE|DESC)\b~i', $s)) {
            return 'read';
        }

        // everything else -> write (INSERT/UPDATE/DELETE/MERGE/...) + unknown statements
        return 'write';
    }
}
