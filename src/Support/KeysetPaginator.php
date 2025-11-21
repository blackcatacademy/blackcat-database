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

/**
 * KeysetPaginator – stable and safe seek-style pagination over a contract view.
 *
 * Features:
 * - Deterministic ORDER BY (primary column + PK tie-breaker).
 * - Correct comparisons for ASC/DESC even when the sort column matches.
 * - Optional NULLS LAST (native on PG, emulated on MySQL/MariaDB).
 * - Input hardening (default WHERE, safe identifier quoting, fixed placeholders without collision).
 *
 * Contracts:
 * - $viewName: contract view/table name without alias (always aliased as "t").
 * - $joins: optional JOIN fragments (already validated, may be empty).
 * - $baseWhere: expression WITHOUT the "WHERE" keyword (empty -> "1=1").
 * - $order: ['col'=>string,'dir'=>'asc'|'desc','pk'=>string,'nullsLast'?:bool]
 * - $cursor: ['colValue'=>mixed,'pkValue'=>mixed] | null
 *
 * @psalm-type OrderSpec = array{col: string, dir: 'asc'|'desc', pk: string, nullsLast?: bool}
 * @psalm-type Cursor = array{colValue: mixed, pkValue: mixed}
 * @psalm-type PageResult = array{0:list<array<string,mixed>>,1:?array{colValue:mixed,pkValue:mixed}}
 */
final class KeysetPaginator
{
    /** Forbidden tokens in `joins`/`baseWhere` fragments (prevents injection there). */
    private const FORBIDDEN_TOKENS_RE = '~(;|--|/\*|\b(WHERE|ORDER\s+BY|LIMIT|OFFSET|RETURNING)\b)~i';

    /**
     * @param Database                     $db
     * @param non-empty-string             $viewName
     * @param string                       $joins
     * @param string                       $baseWhere
     * @param array<string,mixed>          $params
     * @param array{col:string,dir:'asc'|'desc',pk:string, nullsLast?:bool} $order
     * @param array{colValue:mixed,pkValue:mixed}|null $cursor
     * @param int                          $limit
     * @return array{0:array<int,array<string,mixed>>,1:?array{colValue:mixed,pkValue:mixed}}
     */
    public static function paginate(
        Database $db,
        string $viewName,
        string $joins,
        string $baseWhere,
        array $params,
        array $order,
        ?array $cursor,
        int $limit
    ): array {
        // --- Input normalization ---
        $dir = \strtolower((string)$order['dir']);
        $dir = $dir === 'asc' ? 'ASC' : 'DESC';

        $col       = (string)$order['col'];
        $pk        = (string)$order['pk'];
        $nullsLast = (bool)($order['nullsLast'] ?? false);

        // Quoted identifiers: "t"."col" and "t"."pk" (without relying on dotted quotes)
        $colEsc = SqlIdentifier::q($db, 't') . '.' . SqlIdentifier::q($db, $col);
        $pkEsc  = SqlIdentifier::q($db, 't') . '.' . SqlIdentifier::q($db, $pk);
        $cursorColAlias = '__ks_cursor_col';
        $cursorPkAlias  = '__ks_cursor_pk';
        $extraSelect = [
            $colEsc . ' AS ' . SqlIdentifier::q($db, $cursorColAlias),
        ];
        if ($pk === $col) {
            $cursorPkAlias = $cursorColAlias;
        } else {
            $extraSelect[] = $pkEsc . ' AS ' . SqlIdentifier::q($db, $cursorPkAlias);
        }

        // Comparison operator for seek based on direction
        $cmp = $dir === 'ASC' ? '>' : '<';

        // WHERE base (no keywords, comments, or ;)
        $baseWhere = \trim($baseWhere);
        if ($baseWhere === '') {
            $baseWhere = '1=1';
        } else {
            self::guardFragment($baseWhere, 'baseWhere');
            // Extra safety: wrap in parentheses so we can safely append AND clauses
            $baseWhere = '(' . $baseWhere . ')';
        }

        // Joins (validated: must not contain forbidden keywords/comments)
        $joins = \trim($joins);
        if ($joins !== '') {
            self::guardFragment($joins, 'joins');
            // Basic sanity check: require at least one JOIN clause
            if (!\preg_match('~\b(INNER|LEFT|RIGHT|FULL)\s+JOIN\b~i', $joins)) {
                throw new \InvalidArgumentException('joins must contain at least one JOIN clause.');
            }
            $joins = ' ' . $joins . ' ';
        }

        // --- SEEK filtr (cursor) ---
        $seekSql = '';
        $pCol = self::uniqueParam($params, '__ks_cur_col');
        $pPk  = self::uniqueParam($params, '__ks_cur_pk');

        if ($cursor !== null) {
            $colVal = $cursor['colValue'] ?? null;
            $pkVal  = $cursor['pkValue']  ?? null;

            if ($pkVal === null) {
                throw new \InvalidArgumentException('cursor.pkValue must not be NULL.');
            }

            // Special handling of NULL values in the sort column
            if ($colVal === null) {
                if (!$nullsLast) {
                    throw new \InvalidArgumentException('Seek with NULL colValue requires nullsLast=true for deterministic order.');
                }
                // We are in the "NULL segment" at the end – continue only inside this segment via PK
                $seekSql   = " AND ({$colEsc} IS NULL AND {$pkEsc} {$cmp} {$pPk})";
                $params[$pPk] = $pkVal;
            } else {
                if ($col === $pk) {
                    $seekSql   = " AND ({$pkEsc} {$cmp} {$pPk})";
                    $params[$pPk] = $pkVal;
                } else {
                    $seekSql   = " AND ( ({$colEsc} {$cmp} {$pCol}) OR ({$colEsc} = {$pCol} AND {$pkEsc} {$cmp} {$pPk}) )";
                    $params[$pCol] = $colVal;
                    $params[$pPk]  = $pkVal;
                }
            }
        }

        // --- ORDER BY (primary + PK tie-breaker) ---
        $orderPieces = [];
        $orderPieces[] = self::orderPiece($db, $colEsc, $dir, $nullsLast);
        if ($pk !== $col) {
            $orderPieces[] = self::orderPiece($db, $pkEsc, $dir, $nullsLast);
        }
        $orderSql = \implode(', ', $orderPieces);

        // --- LIMIT ---
        $limit = \max(1, (int)$limit);
        $pLim  = self::uniqueParam($params, '__ks_lim');
        $params[$pLim] = $limit;

        // --- Final SQL ---
        $viewEsc = SqlIdentifier::qi($db, $viewName);
        $selectCols = 't.*, ' . \implode(', ', $extraSelect);
        $sql = "SELECT {$selectCols} FROM {$viewEsc} t"
             . $joins
             . "WHERE {$baseWhere}{$seekSql} "
             . "ORDER BY {$orderSql} "
             . "LIMIT {$pLim}";

        // --- Execution and cursor ---
        $rows = \method_exists($db, 'fetchAllWithMeta')
            ? (array)$db->fetchAllWithMeta($sql, $params, ['component'=>'keyset','op'=>'page','view'=>$viewName])
            : (array)$db->fetchAll($sql, $params);
        $next = null;

        if ($rows) {
            $last = $rows[\count($rows) - 1] ?? null;
            if ($last !== null) {
                $colVal = $last[$cursorColAlias] ?? $last[$col] ?? null;
                $pkVal  = $last[$cursorPkAlias]  ?? $last[$pk]  ?? null;
                $next = [
                    'colValue' => $colVal,
                    'pkValue'  => $pkVal,
                ];
            }
        }

        return [$rows, $next];
    }

    // ---------------------------- Internals ----------------------------

    /** Ensure a unique parameter name so it will not collide with user parameters. */
    private static function uniqueParam(array $existing, string $base): string
    {
        $k = ':' . ltrim($base, ':');
        if (!\array_key_exists($k, $existing)) {
            return $k;
        }
        $i = 2;
        do {
            $cand = $k . '_' . $i;
            $i++;
        } while (\array_key_exists($cand, $existing));
        return $cand;
    }

    /** Create an ORDER BY fragment with optional NULLS LAST (PG) or emulation (MySQL/MariaDB). */
    private static function orderPiece(Database $db, string $qualified, string $dir, bool $nullsLast): string
    {
        if (!$nullsLast) {
            return "{$qualified} {$dir}";
        }
        if ($db->isPg()) {
            return "{$qualified} {$dir} NULLS LAST";
        }
        // MySQL/MariaDB – emulate NULLS LAST via (col IS NULL), col DIR
        // (NULL = 1 -> sorts after non-null, then apply the native direction)
        return "({$qualified} IS NULL), {$qualified} {$dir}";
    }

    /** Validate user-provided fragments (no ;, comments, WHERE/ORDER/LIMIT/OFFSET/RETURNING). */
    private static function guardFragment(string $sql, string $label): void
    {
        if (\preg_match(self::FORBIDDEN_TOKENS_RE, $sql)) {
            throw new \InvalidArgumentException($label . ' contains forbidden tokens.');
        }
    }
}
