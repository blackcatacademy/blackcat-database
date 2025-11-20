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

namespace BlackCat\Database\Outbox;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\DatabaseIngressAdapterInterface;
use BlackCat\Database\Support\SqlIdentifier as Ident;

/**
 * OutboxRepository
 *
 * Safe, fully-parameterized SQL outbox for MySQL/PostgreSQL.
 * - No string concatenation of values; everything uses bind parameters.
 * - Microsecond timestamps (CURRENT_TIMESTAMP(6) where available).
 * - Sensible batch limits and trimmed error messages.
 * - Consistent identifier quoting via {@see SqlIdentifier}.
 *
 * Expected `bc_outbox_events` columns:
 *   id BIGSERIAL/BIGINT AUTO PK, created_at timestamptz/TIMESTAMP(6),
 *   available_at timestamptz/TIMESTAMP(6), event_type text/varchar,
 *   payload jsonb/JSON/TEXT, routing_key text/varchar NULL,
 *   tenant text/varchar NULL, trace_id text/varchar NULL,
 *   acked_at timestamptz/TIMESTAMP(6) NULL, fail_count int default 0,
 *   last_error text/varchar NULL
 */
final class OutboxRepository
{
    private const TABLE          = 'bc_outbox_events';
    private const MAX_LIMIT      = 1000;
    private const MAX_ERROR_MSG  = 1000;

    private ?DatabaseIngressAdapterInterface $ingressAdapter = null;
    private ?string $ingressTable = null;

    public function __construct(private Database $db) {}

    public function setIngressAdapter(?DatabaseIngressAdapterInterface $adapter, ?string $table = null): void
    {
        $this->ingressAdapter = $adapter;
        if (\is_string($table) && $table !== '') {
            $this->ingressTable = $table;
        }
    }

    /**
     * Inserts an event into the outbox.
     *
     * @param positive-int|0 $delaySeconds delivery delay in seconds
     */
    public function insert(OutboxRecord $r, int $delaySeconds = 0): void
    {
        $delaySeconds = max(0, $delaySeconds);
        $tbl = $this->tbl();
        $payload = $this->ingressPayload($r->payloadJson);

        if ($this->db->dialect()->isMysql()) {
            $sql = "INSERT INTO {$tbl}
                    (created_at, available_at, event_type, payload, routing_key, tenant, trace_id, fail_count)
                    VALUES (
                        CURRENT_TIMESTAMP,
                        DATE_ADD(CURRENT_TIMESTAMP, INTERVAL :delay SECOND),
                        :t,
                        :p,
                        :rk,
                        :ten,
                        :tr,
                        0
                    )";
            $params = [
                ':delay' => $delaySeconds,
                ':t'  => $r->eventType,
                ':p'  => $payload,
                ':rk' => $r->routingKey,
                ':ten'=> $r->tenant,
                ':tr' => $r->traceId,
            ];
        } else {
            // PostgreSQL: store payload as jsonb
            $sql = "INSERT INTO {$tbl}
                    (created_at, available_at, event_type, payload, routing_key, tenant, trace_id, fail_count)
                    VALUES (
                        CURRENT_TIMESTAMP(6),
                        CURRENT_TIMESTAMP(6) + make_interval(secs => :delay),
                        :t,
                        CAST(:p AS jsonb),
                        :rk,
                        :ten,
                        :tr,
                        0
                    )";
            $params = [
                ':delay' => $delaySeconds,
                ':t'  => $r->eventType,
                ':p'  => $payload,
                ':rk' => $r->routingKey,
                ':ten'=> $r->tenant,
                ':tr' => $r->traceId,
            ];
        }

        $this->db->execute($sql, $params);
    }

    /**
     * Claims a batch of events for delivery.
     * Note: PostgreSQL uses `FOR UPDATE SKIP LOCKED`. MySQL uses a simple SELECT
     * for wider compatibility (avoids version-specific features).
     *
     * @return list<array{id:int|string, payload:mixed, routing_key?:string|null}>
     */
    public function claimBatch(int $limit = 100): array
    {
        $limit = max(1, min(self::MAX_LIMIT, $limit));
        $tbl   = $this->tbl();

        // TODO(crypto-integrations): When manifest coverage hashes are available record
        // them alongside payload so consumers can attest to crypto policy compliance.
        // Select only the necessary columns for the consumer: id, payload, routing_key
        if ($this->db->dialect()->isMysql()) {
            // Compatible variant without SKIP LOCKED (simplest behavior).
            $sql = "SELECT id, payload, routing_key
                    FROM {$tbl}
                    WHERE acked_at IS NULL AND available_at <= CURRENT_TIMESTAMP
                    ORDER BY id ASC
                    LIMIT :__lim";
            $rows = $this->db->fetchAll($sql, [':__lim' => $limit]) ?? [];
            return $rows;
        }

        // PostgreSQL – safely claim rows without blocking consumers
        $sql = "SELECT id, payload, routing_key
                FROM {$tbl}
                WHERE acked_at IS NULL AND available_at <= CURRENT_TIMESTAMP(6)
                ORDER BY id ASC
                FOR UPDATE SKIP LOCKED
                LIMIT :__lim";
        return $this->db->fetchAll($sql, [':__lim' => $limit]) ?? [];
    }

    /** Marks a record as processed (ACK). */
    public function ack(int $id): void
    {
        $tbl = $this->tbl();
        $sql = $this->db->dialect()->isMysql()
            ? "UPDATE {$tbl} SET acked_at = CURRENT_TIMESTAMP WHERE id = :id"
            : "UPDATE {$tbl} SET acked_at = CURRENT_TIMESTAMP(6) WHERE id = :id";
        $this->db->execute($sql, [':id' => $id]);
    }

    /**
     * Marks a record as failed – increments fail_count, stores the message, and pushes available_at forward.
     *
     * @param positive-int|0 $backoffSec
     */
    public function fail(int $id, #[\SensitiveParameter] string $message, int $backoffSec = 60): void
    {
        $tbl   = $this->tbl();
        $msg   = \substr($message, 0, self::MAX_ERROR_MSG);
        $bsec  = max(0, $backoffSec);

        if ($this->db->dialect()->isMysql()) {
            $sql = "UPDATE {$tbl}
                    SET fail_count = fail_count + 1,
                        last_error = :e,
                        available_at = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL :b SECOND)
                    WHERE id = :id";
            $this->db->execute($sql, [':e' => $msg, ':b' => $bsec, ':id' => $id]);
            return;
        }

        $sql = "UPDATE {$tbl}
                SET fail_count = fail_count + 1,
                    last_error = :e,
                    available_at = CURRENT_TIMESTAMP(6) + make_interval(secs => :b)
                WHERE id = :id";
        $this->db->execute($sql, [':e' => $msg, ':b' => $bsec, ':id' => $id]);
    }

    /**
     * Batch cleanup for old ACKed records.
     *
     * @param positive-int $maxRows
     * @param positive-int $retentionSec delete records older than this many seconds (based on available_at)
     * @return int number of deleted rows
     */
    public function cleanup(int $maxRows = 1000, int $retentionSec = 7 * 24 * 3600): int
    {
        $max = max(1, min(10_000, $maxRows));
        $tbl = $this->tbl();

        if ($this->db->dialect()->isMysql()) {
            // MySQL: DELETE ... ORDER BY ... LIMIT
            $sql = "DELETE FROM {$tbl}
                    WHERE acked_at IS NOT NULL
                      AND available_at < (CURRENT_TIMESTAMP - INTERVAL :secs SECOND)
                    ORDER BY id ASC
                    LIMIT :lim";
            return (int)$this->db->execute($sql, [':secs' => $retentionSec, ':lim' => $max]);
        }

        // PostgreSQL: CTE with LIMIT
        $sql = "WITH del AS (
                    SELECT id
                    FROM {$tbl}
                    WHERE acked_at IS NOT NULL
                      AND available_at < (CURRENT_TIMESTAMP(6) - make_interval(secs => :secs))
                    ORDER BY id ASC
                    LIMIT :lim
                )
                DELETE FROM {$tbl} t
                USING del
                WHERE t.id = del.id";
        return (int)$this->db->execute($sql, [':secs' => $retentionSec, ':lim' => $max]);
    }

    // ---------------- Internal helpers ----------------

    private function tbl(): string
    {
        return Ident::q($this->db, self::TABLE);
    }

    private function ingressPayload(string $json): string
    {
        if ($this->ingressAdapter === null || $json === '') {
            return $json;
        }

        $table = $this->ingressTable ?? self::TABLE;
        try {
            $result = $this->ingressAdapter->encrypt($table, ['payload' => $json]);
            if (isset($result['payload']) && \is_string($result['payload'])) {
                return $result['payload'];
            }
        } catch (\Throwable) {
            // best-effort; never impact writes
        }
        return $json;
    }
}
