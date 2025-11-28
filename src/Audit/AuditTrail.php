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

namespace BlackCat\Database\Audit;

use BlackCat\Core\Database;
use BlackCat\Database\Support\Observability;
use BlackCat\Database\Support\SqlIdentifier as Ident;

/**
 * AuditTrail – safe auditing with JSON payloads (PG jsonb, MySQL/MariaDB JSON/LONGTEXT),
 * microsecond timestamps, composite PK support, and Observability integration (corr/tx/svc/op/actor).
 *
 * Goals:
 * - Fully parameterized SQL (no string concatenation of values)
 * - Strong typing and guards (length clamps, normalization)
 * - Microsecond precision timestamps
 * - Compatibility with PG / MySQL / MariaDB (10.4+)
 * - Developer-friendly API and schema installation helpers
 */
final class AuditTrail
{
    /** Maximum column lengths (aligned with the strictest MySQL/MariaDB variant). */
    private const OP_MAX     = 64;
    private const ACTOR_MAX  = 255;
    private const PK_MAX     = 255;

    private int $paramSeq = 0;

    public function __construct(
        private Database $db,
        private string $tblChanges = 'changes',
        private string $tblTx = 'audit_tx',
    ) {}

    /**
     * Persists a row change event.
     *
     * @param string $table logical table name (stored as text, not quoted identifier)
     * @param string|int|array $pk primary key (string/int or composite array)
     * @param string $op 'insert'|'update'|'delete'|... (stored lowercase/trimmed)
     * @param array<string,mixed>|null $before state before the change (or diff via recordDiff())
     * @param array<string,mixed>|null $after state after the change (or diff)
     * @param string|null $actor optional actor (user ID, service, ...)
     * @param array<string,mixed> $meta observability metadata (corr/driver/db, ...)
     */
    public function record(
        string $table,
        string|int|array $pk,
        string $op,
        #[\SensitiveParameter] ?array $before = null,
        #[\SensitiveParameter] ?array $after = null,
        ?string $actor = null,
        array $meta = []
    ): void {
        $meta = Observability::withDefaults($meta, $this->db);

        [$bExpr, $bParam, $bVal] = $this->jsonBinding('b', $before);
        [$aExpr, $aParam, $aVal] = $this->jsonBinding('a', $after);

        $pkStr = \is_array($pk)
            ? $this->safeJsonEncode($pk)
            : (string) $pk;

        $opSan     = $this->normalizeOp($op);
        $actorSan  = $actor !== null && $actor !== '' ? $this->truncate($actor, self::ACTOR_MAX) : null;
        $pkSan     = $this->truncate($pkStr, self::PK_MAX);
        $tableName = $this->truncate($table, self::ACTOR_MAX); // stored as text, clamp for safety

        $tbl = Ident::q($this->db, $this->tblChanges);
        $sql = "INSERT INTO {$tbl}(table_name, pk, op, before_data, after_data, actor, ts)
                VALUES (:t, :pk, :op, {$bExpr}, {$aExpr}, :actor, CURRENT_TIMESTAMP(6))";

        $params = [
            ':t'     => $tableName,
            ':pk'    => $pkSan,
            ':op'    => $opSan,
            ':actor' => $actorSan,
        ];
        if ($bParam !== null) { $params[$bParam] = $bVal; }
        if ($aParam !== null) { $params[$aParam] = $aVal; }

        // Propagate observability meta (corr/svc/op/actor/tx...) and override 'svc'/'op' for the audit channel.
        $this->db->execute($sql, $params);
    }

    /**
     * Transaction-level audit entry (begin/commit/rollback); expects the audit_tx table.
     *
     * @param string $phase 'begin'|'commit'|'rollback'|... (stored lowercase)
     * @param array $meta corr/tx/svc/op/actor/ms (ms = duration)
     */
    public function recordTx(string $phase, array $meta = []): void
    {
        $meta = Observability::withDefaults($meta, $this->db);

        $phaseSan = $this->truncate(\strtolower(\trim($phase)), self::OP_MAX);
        $corr     = (string)($meta['corr']  ?? '');
        $tx       = (string)($meta['tx']    ?? '');
        $svc      = (string)($meta['svc']   ?? '');
        $op       = (string)($meta['op']    ?? '');
        $actor    = (string)($meta['actor'] ?? '');
        $ms       = (int)($meta['ms']       ?? 0);
        if ($ms < 0) { $ms = 0; }

        $tbl = Ident::q($this->db, $this->tblTx);
        $sql = "INSERT INTO {$tbl}(phase, corr, tx, svc, op, actor, at, ms)
                VALUES (:phase, :corr, :tx, :svc, :op, :actor, CURRENT_TIMESTAMP(6), :ms)";

        $this->db->execute($sql, [
            ':phase' => $phaseSan,
            ':corr'  => $corr,
            ':tx'    => $tx,
            ':svc'   => $svc,
            ':op'    => $op,
            ':actor' => $this->truncate($actor, self::ACTOR_MAX),
            ':ms'    => $ms,
        ]);
    }

    /**
     * Persists only the delta (changed keys) – useful for large objects.
     *
     * @param array<string,mixed> $before
     * @param array<string,mixed> $after
     */
    public function recordDiff(
        string $table,
        string|int|array $pk,
        array $before,
        array $after,
        ?string $actor = null,
        array $meta = []
    ): void {
        $changed = [];
        $allKeys = \array_unique(\array_merge(\array_keys($before), \array_keys($after)));
        foreach ($allKeys as $k) {
            $b = $before[$k] ?? null;
            $a = $after[$k]  ?? null;
            if ($b !== $a) {
                $changed[$k] = ['from' => $b, 'to' => $a];
            }
        }
        // Store the diff in both columns (before/after) for readability.
        $this->record($table, $pk, 'update', ['_diff' => $changed], ['_diff' => $changed], $actor, $meta);
    }

    /**
     * Purges old entries from the change table (not from audit_tx).
     * Note: Large deletes can be expensive; schedule in batches/CRON.
     */
    public function purgeOlderThanDays(int $days): int
    {
        $days = \max(1, $days);
        $tbl  = Ident::q($this->db, $this->tblChanges);

        if ($this->db->isPg()) {
            $sql = "DELETE FROM {$tbl} WHERE ts < (CURRENT_TIMESTAMP(6) - make_interval(days => :d))";
            return $this->db->exec($sql, [':d' => $days]);
        }

        // MySQL/MariaDB – parameters inside INTERVAL are common; fallback to precomputed DATETIME if needed.
        $sql = "DELETE FROM {$tbl} WHERE ts < DATE_SUB(CURRENT_TIMESTAMP(6), INTERVAL :d DAY)";
        return $this->db->exec($sql, [':d' => $days]);
    }

    /**
     * Creates the audit tables for the current dialect (idempotent).
     * Uses quoted identifiers for table and index names.
     */
    public function installSchema(): void
    {
        $tblCh = Ident::q($this->db, $this->tblChanges);
        $tblTx = Ident::q($this->db, $this->tblTx);

        $ixChanges = Ident::q($this->db, $this->indexName("ix_{$this->tblChanges}_table_pk_ts"));
        $ixTxCorr  = Ident::q($this->db, $this->indexName("ix_{$this->tblTx}_corr_at"));

        if ($this->db->isPg()) {
            // changes
            $this->db->exec("
CREATE TABLE IF NOT EXISTS {$tblCh} (
    id          bigserial PRIMARY KEY,
    ts          timestamptz(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    table_name  text NOT NULL,
    pk          text NOT NULL,
    op          text NOT NULL,
    actor       text NULL,
    before_data jsonb NULL,
    after_data  jsonb NULL
)");
            $this->db->exec("CREATE INDEX IF NOT EXISTS {$ixChanges} ON {$tblCh} (table_name, pk, ts DESC)");

            // audit_tx
            $this->db->exec("
CREATE TABLE IF NOT EXISTS {$tblTx} (
    id     bigserial PRIMARY KEY,
    at     timestamptz(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    phase  text NOT NULL,
    corr   text NOT NULL,
    tx     text NOT NULL,
    svc    text NULL,
    op     text NULL,
    actor  text NULL,
    ms     integer NOT NULL DEFAULT 0
)");
            $this->db->exec("CREATE INDEX IF NOT EXISTS {$ixTxCorr} ON {$tblTx} (corr, at DESC)");
            return;
        }

        // MySQL / MariaDB 10.4+
        $this->db->exec("
CREATE TABLE IF NOT EXISTS {$tblCh} (
    id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ts           TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    table_name   VARCHAR(255) NOT NULL,
    pk           VARCHAR(255) NOT NULL,
    op           VARCHAR(64)  NOT NULL,
    actor        VARCHAR(255) NULL,
    before_data  JSON NULL,
    after_data   JSON NULL
) ENGINE=InnoDB
");
        // IF NOT EXISTS exists in MySQL 8+, not in MariaDB 10.4 – best-effort with try/catch.
        try {
            $this->db->exec("CREATE INDEX IF NOT EXISTS {$ixChanges} ON {$tblCh} (table_name, pk, ts)");
        } catch (\Throwable $_) {
            // no-op
        }

        $this->db->exec("
CREATE TABLE IF NOT EXISTS {$tblTx} (
    id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    at     TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    phase  VARCHAR(32)  NOT NULL,
    corr   VARCHAR(128) NOT NULL,
    tx     VARCHAR(64)  NOT NULL,
    svc    VARCHAR(64)  NULL,
    op     VARCHAR(64)  NULL,
    actor  VARCHAR(255) NULL,
    ms     INT NOT NULL DEFAULT 0
) ENGINE=InnoDB
");
        try {
            $this->db->exec("CREATE INDEX IF NOT EXISTS {$ixTxCorr} ON {$tblTx} (corr, at)");
        } catch (\Throwable $_) {
            // no-op
        }
    }

    // ---------------- Internal helpers ----------------

    /**
     * Returns [SQL expression, parameter name (or null), value] for dialect-aware JSON storage.
     *
     * @param string $key suffix used to generate a unique parameter name (e.g. 'b' / 'a')
     * @return array{0:string,1:?string,2:mixed}
     */
    private function jsonBinding(string $key, ?array $data): array
    {
        if ($data === null) {
            return ['NULL', null, null];
        }
        $json = $this->safeJsonEncode($data);
        $param = ':__json_' . $key . '_' . $this->nextParamId();
        if ($this->db->isPg()) {
            return ['CAST(' . $param . ' AS jsonb)', $param, $json];
        }
        return [$param, $param, $json]; // MySQL/MariaDB (JSON alias maps to LONGTEXT on MariaDB 10.4)
    }

    /** Safe JSON encoding helper that throws on error. */
    private function safeJsonEncode(mixed $value): string
    {
        $json = \json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($json === false) {
            throw new \RuntimeException('JSON encoding failed: ' . \json_last_error_msg());
        }
        return $json;
    }

    /** Normalizes an operation name (lowercase + length clamp). */
    private function normalizeOp(string $op): string
    {
        $op = \strtolower(\trim($op));
        // allow a-z0-9 _ - /
        $op = \preg_replace('~[^a-z0-9_\-/]+~', '-', $op) ?? $op;
        return $this->truncate($op, self::OP_MAX);
    }

    /** Multibyte-safe truncation without breaking UTF-8 sequences. */
    private function truncate(string $s, int $max): string
    {
        if (\strlen($s) <= $max) {
            return $s;
        }

        $sub = \substr($s, 0, $max);

        // Multibyte-safe fallback: if mb_* is missing, revert to byte-cut (most values are ASCII/UTF-8 safe)
        if (\function_exists('mb_check_encoding') && \function_exists('mb_substr')) {
            return \mb_check_encoding($sub, 'UTF-8') ? $sub : \mb_substr($s, 0, $max, 'UTF-8');
        }

        return $sub;
    }

    /** Simple sequencer for unique parameter names. */
    private function nextParamId(): int
    {
        return ++$this->paramSeq;
    }

    /** Generates a safe index name (slug) for different tables. */
    private function indexName(string $suggested): string
    {
        $slug = \strtolower(\preg_replace('~[^a-zA-Z0-9_]+~', '_', $suggested) ?? $suggested);
        return \trim($slug, '_');
    }
}
