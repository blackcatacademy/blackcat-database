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

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\BulkUpsertRepository;
use BlackCat\Database\Contracts\DatabaseIngressAdapterInterface;

/**
 * Efficient bulk UPSERT for Postgres and MySQL/MariaDB.
 *
 * Host repo:
 *  - property Database $db
 *  - method def(): class-string (Definitions FQN)
 * Optional:
 *  - method upsertUpdateColumns(): string[]
 *  - method afterWrite(): void
 *  - RepositoryCacheInvalidationTrait::invalidateSelfCache()
 */
trait BulkUpsertTrait
{
    /**
     * @param array<int,array<string,mixed>> $rows
     * @param string[] $keys conflict keys override (optional)
     * @param string[] $updateColumns update columns override (optional)
     */
    public function upsertMany(array $rows, array $keys = [], array $updateColumns = []): void
    {
        if (!$rows) return;

        $db  = $this->db;
        $def = $this->def();
        $table = (string)$def::table();

        $rows = $this->ingressTransformRows($table, $rows);

        // 1) Collect full column set across rows (first-seen order, stable within input).
        $allCols = [];
        foreach ($rows as $r) {
            foreach ($r as $c => $_) { $allCols[$c] = true; }
        }
        $allCols = array_values(array_keys($allCols));

        // Optional definition-based whitelist hardening
        $allCols = $this->filterKnownColumns($def, $allCols);

        // 2) Conflict keys & update columns.
        $pkCols   = \method_exists($def, 'pkColumns') ? (array)$def::pkColumns() : [(string)$def::pk()];
        $conflictSource = $keys ?: (\method_exists($def, 'upsertKeys') ? (array)$def::upsertKeys() : $pkCols);
        $conflict = $this->filterKnownColumns($def, array_values(array_unique(array_map('strval', $conflictSource))));

        $updateCols =
            $updateColumns && \is_array($updateColumns)
            ? $updateColumns
            : (
                /** @phpstan-ignore-next-line phpstan cannot see consuming repo methods */
                \method_exists($this, 'upsertUpdateColumns')
                ? (array)$this->upsertUpdateColumns()
                : array_values(array_diff($allCols, $conflict, ['created_at']))
            );
        $updateCols = array_values(array_unique(array_map('strval', $updateCols)));
        $updateCols = $this->filterKnownColumns($def, $updateCols);

        // updated_at auto bump if present in defs
        $updatedAt = null;
        if (\method_exists($def, 'hasColumn')) {
            if ($def::hasColumn('updated_at')) $updatedAt = 'updated_at';
            elseif (\method_exists($def, 'updatedAtColumn')) $updatedAt = (string)$def::updatedAtColumn();
        }

        // Guard PG: ON CONFLICT requires keys
        if ($db->isPg() && !$conflict) {
            throw new \InvalidArgumentException('PostgreSQL bulk UPSERT requires non-empty conflictKeys.');
        }

        // 3) Chunk respecting driver parameter limits (PG 32767; MySQL safe ~60k).
        $colsPerRow = max(1, count($allCols));
        $maxParams  = $db->isPg() ? 30000 : 60000;
        $maxRows    = max(1, intdiv($maxParams, $colsPerRow));
        $chunks     = array_chunk($rows, min(1000, $maxRows)); // sane chunk size for locks/logs

        foreach ($chunks as $chunk) {
            $chunk = $this->ingressTransformRows($table, $chunk);
            [$sql, $params] = $this->buildBulkUpsert(
                $db,
                $table,
                $allCols,
                $chunk,
                $conflict,
                $updateCols,
                $updatedAt
            );

            // Short robust retry for transient errors.
            $run = function () use ($db, $sql, $params, $def, $chunk) {
                /** @phpstan-ignore-next-line optional db extension */
                if (\method_exists($db, 'executeWithMeta')) {
                    return $db->executeWithMeta($sql, $params, [
                        'svc'   => 'repo',
                        'op'    => 'bulk_upsert',
                        'table' => (string)$def::table(),
                        'rows'  => \count($chunk),
                    ]);
                }
                return $db->execute($sql, $params);
            };

            /** @phpstan-ignore-next-line runtime hook uses Retry generic */
            Retry::runAdvanced(
                $run,
                attempts: 3,
                initialMs: 25,
                factor: 2.0,
                maxMs: 1000,
                jitter: 'full'
            );
        }

        // 4) Post-write hooks (best-effort).
        /** @phpstan-ignore-next-line repo may provide hook */
        if (\method_exists($this, 'afterWrite')) {
            try { $this->afterWrite(); } catch (\Throwable) {}
        }
        /** @phpstan-ignore-next-line repo may provide cache hook */
        if (\method_exists($this, 'invalidateSelfCache')) {
            try { $this->invalidateSelfCache(); } catch (\Throwable) {}
        }
    }

    /**
     * @param array<int,array<string,mixed>> $rows
     * @return array{0:string,1:array<string,mixed>}
     */
    private function buildBulkUpsert(
        Database $db,
        string $table,
        array $cols,
        array $rows,
        array $conflictKeys,
        array $updateCols,
        ?string $updatedAt
    ): array {
        $tbl    = $this->qi($db, $table);
        $colSql = implode(', ', array_map(fn($c) => $this->qid($db, $c), $cols));

        // VALUES (...), named params :r{row}c{col}
        $params = [];
        $values = [];
        foreach ($rows as $i => $r) {
            $ph = [];
            foreach ($cols as $j => $c) {
                $name = ':r' . $i . 'c' . $j;
                $ph[] = $name;
                $params[$name] = $r[$c] ?? null;
            }
            $values[] = '(' . implode(', ', $ph) . ')';
        }

        if ($db->isPg()) {
            $keysEsc = implode(', ', array_map(fn($c) => $this->qid($db, $c), $conflictKeys));

            $sets = [];
            foreach ($updateCols as $c) {
                if (in_array($c, $cols, true)) {
                    $qc = $this->qid($db, $c);
                    $sets[] = "{$qc} = EXCLUDED.{$qc}";
                }
            }
            if ($updatedAt && !in_array($updatedAt, $updateCols, true)) {
                $sets[] = $this->qid($db, $updatedAt) . ' = CURRENT_TIMESTAMP(6)';
            }

            $sql = "INSERT INTO {$tbl} ({$colSql}) VALUES " . implode(', ', $values)
                 . " ON CONFLICT ({$keysEsc}) "
                 . ($sets ? 'DO UPDATE SET ' . implode(', ', $sets) : 'DO NOTHING');

            return [$sql, $params];
        }

        // MySQL/MariaDB
        $isMaria  = DbVendor::isMaria($db);
        $ver      = $db->serverVersion();
        // Prefer alias path when version unknown to avoid VALUES() and ambiguity on new MySQL.
        $useAlias = !$isMaria && ($ver === null || \version_compare($ver, '8.0.20', '>='));
        if (\getenv('BC_UPSERT_DEBUG') === '1') {
            \error_log("[upsert] bulk dialect=" . ($isMaria ? 'maria' : 'mysql') . " ver=" . ($ver ?? 'null') . " useAlias=" . ($useAlias ? '1' : '0'));
        }
        $alias    = '_new';
        $tblPref  = $tbl . '.';

        $set = [];

        foreach ($updateCols as $c) {
            if (!in_array($c, $cols, true)) continue;
            $lhs = $tblPref . $this->qid($db, $c);
            if ($useAlias) {
                $col = $this->qid($db, $c);
                $set[] = $lhs . ' = ' . $alias . '.' . $col;
            } else {
                $col = $this->qid($db, $c);
                $set[] = $lhs . ' = VALUES(' . $col . ')';
            }
        }
        if ($updatedAt && !in_array($updatedAt, $updateCols, true)) {
            $set[] = $tblPref . $this->qid($db, $updatedAt) . ' = CURRENT_TIMESTAMP(6)';
        }
        if (!$set) {
            // No-op update to trigger duplicate handling
            $firstCol = $conflictKeys[0] ?? $cols[0];
            $first    = $tblPref . $this->qid($db, $firstCol);
            $set[]    = $first . ' = ' . $first;
        }

        $sql    = "INSERT INTO {$tbl} ({$colSql}) VALUES " . implode(', ', $values)
                . ($useAlias ? " AS {$alias}" : '')
                . " ON DUPLICATE KEY UPDATE " . implode(', ', $set);

        return [$sql, $params];
    }

    /**
     * @param array<int,array<string,mixed>> $rows
     * @return array<int,array<string,mixed>>
     */
    private function ingressTransformRows(string $table, array $rows): array
    {
        $adapter = $this->resolveIngressAdapter();
        if ($adapter === null || $rows === []) {
            return $rows;
        }

        return array_map(
            fn(array $row) => $adapter->encrypt($table, $row),
            $rows
        );
    }

    private function resolveIngressAdapter(): ?DatabaseIngressAdapterInterface
    {
        /** @phpstan-ignore-next-line consuming repo may have property */
        if (\property_exists($this, 'cryptoIngressAdapter')) {
            $adapter = $this->{'cryptoIngressAdapter'};
            if ($adapter instanceof DatabaseIngressAdapterInterface) {
                return $adapter;
            }
        }

        /** @phpstan-ignore-next-line consuming repo may implement */
        if (\method_exists($this, 'getIngressAdapter')) {
            try {
                $adapter = $this->getIngressAdapter();
                if ($adapter instanceof DatabaseIngressAdapterInterface) {
                    return $adapter;
                }
            } catch (\Throwable) {
                return null;
            }
        }

        return null;
    }

    /* =========================== helpers =========================== */

    /** Filter columns by definition when available; otherwise passthrough. */
    private function filterKnownColumns(string $def, array $cols): array
    {
        $cols = array_values(array_filter(array_map('strval', $cols), fn($c) => $c !== ''));
        if (!$cols) return $cols;

        // Prefer hasColumn(); fallback to columns() list if available.
        if (\method_exists($def, 'hasColumn')) {
            return array_values(array_filter($cols, fn($c) => $def::hasColumn($c)));
        }
        if (\method_exists($def, 'columns')) {
            $allowed = array_fill_keys(array_map('strtolower', (array)$def::columns()), true);
            return array_values(array_filter($cols, fn($c) => isset($allowed[strtolower($c)])));
        }
        return $cols;
    }

    /** Quote "schema.table" into driver-aware quoted parts. */
    private function qi(Database $db, string $ident): string
    {
        $parts = explode('.', $ident);
        return implode('.', array_map(fn(string $p) => $this->qid($db, $p), $parts));
    }

    /** Quote single identifier with driver-aware fallback; strips existing quotes. */
    private function qid(Database $db, string $name): string
    {
        $raw = $this->stripQuotes(trim($name));
        try {
            return $db->quoteIdent($raw);
        } catch (\Throwable) {
            // Fallback by dialect
            if ($db->isPg()) {
                return '"' . str_replace('"','""', $raw) . '"';
            }
            return '`' . str_replace('`','``', $raw) . '`';
        }
    }

    private function stripQuotes(string $id): string
    {
        $n = strlen($id);
        if ($n >= 2 && $id[0] === '"' && $id[$n-1] === '"') return substr($id, 1, -1);
        if ($n >= 2 && $id[0] === '`' && $id[$n-1] === '`') return substr($id, 1, -1);
        return $id;
    }
}
