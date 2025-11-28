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

final class UpsertBuilder
{
    /**
     * @param array<string,mixed> $row
     * @param string[] $conflictKeys
     * @param string[] $updateCols
     * @return array{0:string,1:array<string,mixed>}
     */
    public static function buildRow(
        Database $db,
        string $table,
        array $row,
        array $conflictKeys,
        array $updateCols,
        ?string $updatedAt
    ): array {
        if ($row === []) {
            throw new \InvalidArgumentException('UPSERT requires non-empty $row.');
        }

        // Normalize input -> stable ordering with no duplicates
        $updateCols   = \array_values(\array_unique(\array_map('strval', $updateCols)));
        $conflictKeys = \array_values(\array_unique(\array_map('strval', $conflictKeys)));

        $cols = \array_keys($row);
        \sort($cols);

        $tbl    = self::qi($db, $table);
        $colSql = \implode(', ', \array_map(fn($c) => self::q($db, $c), $cols));

        // Safe placeholders :c0, :c1, ...
        $params = [];
        $ph     = [];
        foreach ($cols as $i => $c) {
            $name = ':c' . $i;
            $ph[] = $name;
            $params[$name] = $row[$c] ?? null;
        }
        $phSql = \implode(', ', $ph);

        if ($db->isPg() && !$conflictKeys) {
            throw new \InvalidArgumentException('PostgreSQL UPSERT requires non-empty $conflictKeys.');
        }

        // ---------------- Postgres ----------------
        if ($db->isPg()) {
            $keysEsc = \implode(', ', \array_map(fn($c) => self::q($db, $c), $conflictKeys));

            $set = [];
            foreach ($updateCols as $c) {
                if (\array_key_exists($c, $row)) {
                    $qc = self::q($db, $c);
                    $set[] = "{$qc} = EXCLUDED.{$qc}";
                }
            }
            if ($updatedAt && !\in_array($updatedAt, $updateCols, true)) {
                $set[] = self::q($db, $updatedAt) . ' = CURRENT_TIMESTAMP(6)';
            }

            $sql = self::sqlJoin([
                "INSERT INTO {$tbl} ({$colSql})",
                "VALUES ({$phSql})",
                "ON CONFLICT ({$keysEsc})",
                $set ? 'DO UPDATE SET ' . \implode(', ', $set) : 'DO NOTHING',
            ]);

            return [$sql, $params];
        }

        // ---------------- MySQL / MariaDB ----------------
        $isMaria  = DbVendor::isMaria($db);
        $ver      = $db->serverVersion();
        $useAlias = !$isMaria && $ver !== null && \version_compare($ver, '8.0.20', '>=');
        $alias    = '_new';

        $set = [];
        foreach ($updateCols as $c) {
            if (!\array_key_exists($c, $row)) {
                continue;
            }
            $qc = self::q($db, $c);
            if ($useAlias) {
                $set[] = "{$qc} = {$alias}.{$qc}";
            } else {
                $set[] = "{$qc} = VALUES({$qc})";
            }
        }
        if ($updatedAt && !\in_array($updatedAt, $updateCols, true)) {
            $set[] = self::q($db, $updatedAt) . ' = CURRENT_TIMESTAMP(6)';
        }
        if (!$set) {
            // No-op update to trigger duplicate handling: use the first conflict key (or the first column)
            $firstKey = $conflictKeys[0] ?? $cols[0];
            $qf = self::q($db, $firstKey);
            $set[] = "{$qf} = {$qf}";
        }

        $sql = self::sqlJoin([
            "INSERT INTO {$tbl} ({$colSql})",
            "VALUES ({$phSql})" . ($useAlias ? " AS {$alias}" : ''),
            "ON DUPLICATE KEY UPDATE " . \implode(', ', $set),
        ]);

        return [$sql, $params];
    }

    /**
     * @param array<string,mixed> $row
     * @param string[] $keyCols
     * @param string[] $updateCols
     * @return array{0:string,1:array<string,mixed>}
     */
    public static function buildByKeys(
        Database $db,
        string $table,
        array $row,
        array $keyCols,
        array $updateCols,
        ?string $updatedAt
    ): array {
        // Value validation is the caller's responsibility – this method only builds SQL
        return self::buildRow($db, $table, $row, $keyCols, $updateCols, $updatedAt);
    }

    /**
     * Append RETURNING clause when supported (PG; MySQL 8.0.21+/MariaDB 10.5+).
     * @param array<int,string> $columns  e.g. ['*'] or ['id','updated_at']
     */
    public static function addReturning(Database $db, string $sql, array $columns = ['*']): string
    {
        try {
            $dial = $db->dialect();
            /** @var string $dv */
            $dv   = $dial->value; // 'mysql' | 'postgres'
            $ver  = $db->serverVersion();

            if (\BlackCat\Database\SqlDialect::supportsInsertReturningVersioned($dv, $ver)) {
                $list = ($columns === ['*'])
                    ? '*'
                    : \implode(', ', \array_map(fn($c) => self::q($db, (string)$c), $columns));
                return \rtrim($sql) . ' RETURNING ' . $list;
            }
        } catch (\Throwable) {
            // be quiet – when in doubt, skip RETURNING
        }
        return $sql;
    }

    /**
     * Convenience: buildRow() + optional RETURNING (when supported).
     * @param array<int,string> $returning ['*'] or list of columns
     * @return array{0:string,1:array<string,mixed>}
     */
    public static function buildRowReturning(
        Database $db,
        string $table,
        array $row,
        array $conflictKeys,
        array $updateCols,
        ?string $updatedAt,
        array $returning = ['*']
    ): array {
        [$sql, $params] = self::buildRow($db, $table, $row, $conflictKeys, $updateCols, $updatedAt);
        $sql = self::addReturning($db, $sql, $returning);
        return [$sql, $params];
    }

    /* ====================== Internal helpers ====================== */

    private static function q(Database $db, string $ident): string
    {
        return SqlIdentifier::q($db, $ident);
    }

    private static function qi(Database $db, string $ident): string
    {
        return SqlIdentifier::qi($db, $ident);
    }

    /** Joins SQL parts with single spaces and trims them to avoid fragile concatenation. */
    private static function sqlJoin(array $parts): string
    {
        $parts = \array_map(static fn($p) => \trim((string)$p), $parts);
        $parts = \array_filter($parts, static fn($p) => $p !== '');
        return \implode(' ', $parts);
    }
}
