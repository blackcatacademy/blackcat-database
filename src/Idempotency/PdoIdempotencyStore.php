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

namespace BlackCat\Database\Idempotency;

use BlackCat\Core\Database;
use BlackCat\Database\Support\SqlIdentifier as Ident;

/**
 * PDO-backed IdempotencyStore.
 *
 * Safe, fully parameterized, and dialect-aware (PostgreSQL/MySQL).
 * - `begin()` performs an atomic create-if-absent (PG: ON CONFLICT DO NOTHING, MySQL: ON DUPLICATE KEY).
 * - `commit()` persists JSON result payloads and marks the record as **success**.
 * - `fail()` records the error payload in JSON and marks the record as **failed**.
 * - `get()` returns status + result (or null if the entry does not exist).
 *
 * Expected `bc_idempotency` table schema:
 *   id_key VARCHAR(...) PRIMARY KEY/UNIQUE,
 *   status VARCHAR(32) NOT NULL,            -- 'in_progress'|'success'|'failed'
 *   result_json JSON/jsonb/TEXT NULL,
 *   created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
 *   updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
 *
 * Note: legacy rows with status 'done' are mapped to 'success'.
 */
final class PdoIdempotencyStore implements IdempotencyStore
{
    public function __construct(private Database $db) {}

    /**
     * {@inheritDoc}
     * @phpstan-return array{
     *   status: 'in_progress'|'success'|'failed',
     *   result?: array<string,mixed>|null,
     *   reason?: non-empty-string|null,
     *   startedAt?: int,
     *   completedAt?: int
     * }|null
     */
    public function get(#[\SensitiveParameter] string $key): ?array
    {
        $tbl = $this->tbl();
        $sql = "SELECT status, result_json FROM {$tbl} WHERE id_key = :k LIMIT 1";
        $row = $this->db->fetch($sql, [':k' => $key]);
        if (!$row) {
            return null;
        }
        /** @phpstan-var 'in_progress'|'success'|'failed' $status */
        $status = $this->normalizeStatus((string)($row['status'] ?? ''));
        $json   = $row['result_json'] ?? null;

        // Some drivers return jsonb as an already decoded array; handle both representations.
        $result = null;
        if (\is_array($json)) {
            /** @var array<string,mixed> $json */
            $result = $json;
        } elseif ($json !== null && $json !== '') {
            $result = \json_decode((string)$json, true) ?: null;
        }

        $out = [
            'status' => $status,
            'result' => $result,
        ];
        // optional keys (reason/startedAt/completedAt) are omitted when unknown
        return $out;
    }

    /**
     * {@inheritDoc}
     * Note: TTL parameter is ignored here (this implementation does not track expires_at).
     */
    public function begin(#[\SensitiveParameter] string $key, int $ttlSeconds = 3600): bool
    {
        $tbl = $this->tbl();

        if ($this->db->dialect()->isMysql()) {
            // Safer than INSERT IGNORE: does not swallow other errors; duplicate key performs no change.
            // Affected rows: 1 = inserted, 0/2 = duplicate key (driver-dependent), so return true only for 1.
            $sql = "INSERT INTO {$tbl} (id_key, status, result_json, created_at, updated_at)
                    VALUES (:k, 'in_progress', NULL, CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6))
                    ON DUPLICATE KEY UPDATE id_key = id_key";
            $n = (int)$this->db->execute($sql, [':k' => $key]);
            return $n === 1;
        }

        // PostgreSQL: ON CONFLICT DO NOTHING
        $sql = "INSERT INTO {$tbl} (id_key, status, result_json, created_at, updated_at)
                VALUES (:k, 'in_progress', NULL, CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6))
                ON CONFLICT (id_key) DO NOTHING";
        $n = (int)$this->db->execute($sql, [':k' => $key]);
        return $n === 1;
    }

    /** {@inheritDoc} */
    public function commit(#[\SensitiveParameter] string $key, #[\SensitiveParameter] array $result): void
    {
        $tbl = $this->tbl();
        $json = $this->encodeJson($result);

        if ($this->db->dialect()->isMysql()) {
            $sql = "UPDATE {$tbl}
                    SET status = 'success', result_json = :r, updated_at = CURRENT_TIMESTAMP(6)
                    WHERE id_key = :k";
            $this->db->execute($sql, [':k' => $key, ':r' => $json]);
            return;
        }

        // PostgreSQL: casting to jsonb is beneficial when the column uses jsonb
        $sql = "UPDATE {$tbl}
                SET status = 'success', result_json = CAST(:r AS jsonb), updated_at = CURRENT_TIMESTAMP(6)
                WHERE id_key = :k";
        $this->db->execute($sql, [':k' => $key, ':r' => $json]);
    }

    /** {@inheritDoc} */
    public function fail(#[\SensitiveParameter] string $key, #[\SensitiveParameter] string $reason): void
    {
        $tbl = $this->tbl();
        $reason = \trim($reason);
        if ($reason === '') {
            $reason = 'unknown';
        }
        $payload = ['error' => $reason];
        $json = $this->encodeJson($payload);

        if ($this->db->dialect()->isMysql()) {
            $sql = "UPDATE {$tbl}
                    SET status = 'failed', result_json = :r, updated_at = CURRENT_TIMESTAMP(6)
                    WHERE id_key = :k";
            $this->db->execute($sql, [':k' => $key, ':r' => $json]);
            return;
        }

        $sql = "UPDATE {$tbl}
                SET status = 'failed', result_json = CAST(:r AS jsonb), updated_at = CURRENT_TIMESTAMP(6)
                WHERE id_key = :k";
        $this->db->execute($sql, [':k' => $key, ':r' => $json]);
    }

    // ---------------- Internal helpers ----------------

    private function tbl(): string
    {
        // Safely quote the table identifier across dialects.
        return Ident::qi($this->db, 'bc_idempotency');
    }

    private function encodeJson(mixed $value): string
    {
        $json = \json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($json === false) {
            throw new \RuntimeException('IdempotencyStore: JSON encoding failed: ' . \json_last_error_msg());
        }
        return $json;
    }

    /**
     * @return 'in_progress'|'success'|'failed'
     */
    private function normalizeStatus(string $s): string
    {
        $s = \strtolower(\trim($s));
        if ($s === 'done') {
            return self::STATUS_SUCCESS; // backward compatibility
        }
        return \in_array($s, [self::STATUS_IN_PROGRESS, self::STATUS_SUCCESS, self::STATUS_FAILED], true)
            ? $s
            : self::STATUS_FAILED; // fallback to "failed" for unknown states
    }

    public function purgeOlderThan(\DateInterval $age): int
    {
        $tbl = $this->tbl();
        $cut = (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->sub($age);
        $params = [':cut' => $cut->format('Y-m-d H:i:s.u')];

        if ($this->db->dialect()->isMysql()) {
            $sql = "DELETE FROM {$tbl} WHERE updated_at < :cut";
            return (int)$this->db->execute($sql, $params);
        }

        $sql = "DELETE FROM {$tbl} WHERE updated_at < :cut::timestamptz";
        return (int)$this->db->execute($sql, $params);
    }
}
