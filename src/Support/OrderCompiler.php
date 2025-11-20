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

/**
 * OrderCompiler – universal, safe ORDER BY builder for:
 * - PostgreSQL, MySQL/MariaDB, SQLite, SQL Server (fallback via CASE WHEN … IS NULL …)
 *
 * DSL input (string):
 *   "created_at DESC NULLS LAST, id DESC"
 *
 * Array input:
 *   [
 *     ['expr' => 'created_at', 'dir' => 'DESC', 'nulls' => 'LAST'],
 *     ['expr' => 'id',         'dir' => 'DESC', 'nulls' => 'AUTO'],
 *   ]
 *
 * Features:
 * - Stable ordering with a tie-breaker (PK) when $stable=true.
 * - Safely prefixes aliases (only for "bare" identifiers); expressions/functions stay untouched.
 * - Dialect-specific NULLS FIRST/LAST: PG natively, others via CASE WHEN IS NULL …
 * - Accepts input with/without "ORDER BY", robust parser for parentheses and quotes.
 */
final class OrderCompiler
{
    /**
     * @param string|array<array{expr:string,dir?:string,nulls?:string}>|null $order
     *        - DSL string, an array of structures (see example above), or null/empty.
     * @param string      $dialect  'postgres'|'pgsql'|'postgresql'| 'mysql'|'mariadb'| 'sqlite'| 'sqlserver'|...
     * @param string|null $alias    Optional table alias for prefixing bare identifiers.
     * @param string|null $tiePk    Optional PK name/expression for stabilization tie-breaker.
     * @param bool        $stable   Add tie-breaker when it is missing from items.
     * @param int         $maxTerms Safety limit for number of ORDER BY items (0 = unlimited).
     *
     * @return string " ORDER BY …" or an empty string.
     */
    public static function compile(
        string|array|null $order,
        string $dialect,
        ?string $alias = null,
        ?string $tiePk = null,
        bool $stable = false,
        int $maxTerms = 0
    ): string {
        $items = self::parseItems($order);
        $alias = self::safeAlias($alias);
        if ($maxTerms > 0 && \count($items) > $maxTerms) {
            $items = \array_slice($items, 0, $maxTerms);
        }

        if (!$items) {
            if ($stable && $tiePk) {
                $pkExpr = self::maybePrefix($tiePk, $alias);
                return " ORDER BY {$pkExpr} ASC";
            }
            return '';
        }

        $isPg  = self::isPostgres($dialect);
        $parts = [];
        $hasPk = false;

        foreach ($items as $it) {
            $exprRaw = (string)($it['expr'] ?? '');
            if ($exprRaw === '') {
                continue;
            }

            $expr  = self::maybePrefix($exprRaw, $alias);
            $dir   = self::normDir($it['dir'] ?? 'ASC');
            $nulls = self::normNulls($it['nulls'] ?? 'AUTO');

            if ($tiePk && self::exprEquals($exprRaw, $tiePk, $alias)) {
                $hasPk = true;
            }

            if ($nulls !== 'AUTO') {
                if ($isPg) {
                    $parts[] = "{$expr} {$dir} NULLS {$nulls}";
                } else {
                    // Fallback pro MySQL/MariaDB/SQLite/SQL Server
                    if ($nulls === 'LAST') {
                        // NULLS LAST → non-null values first, then nulls
                        $parts[] = "CASE WHEN ({$expr}) IS NULL THEN 1 ELSE 0 END ASC";
                    } else { // FIRST
                        // NULLS FIRST → nulls first, then non-null values
                        $parts[] = "CASE WHEN ({$expr}) IS NULL THEN 0 ELSE 1 END ASC";
                    }
                    $parts[] = "{$expr} {$dir}";
                }
            } else {
                $parts[] = "{$expr} {$dir}";
            }
        }

        if ($stable && $tiePk && !$hasPk) {
            $dirForPk = self::guessTieBreakerDir($items) ?? 'ASC';
            $pkExpr   = self::maybePrefix($tiePk, $alias);
            $parts[]  = "{$pkExpr} {$dirForPk}";
        }

        return $parts ? (' ORDER BY ' . \implode(', ', $parts)) : '';
    }

    /**
     * Normalizuje vstup (string|array|null) na itemy:
     * @return list<array{expr:string,dir:string,nulls:string}>
     */
    public static function parseItems(string|array|null $order): array
    {
        if (\is_array($order)) {
            $out = [];
            foreach ($order as $it) {
                if (!\is_array($it) || empty($it['expr'])) {
                    continue;
                }
                $out[] = [
                    'expr'  => \trim((string)$it['expr']),
                    'dir'   => self::normDir((string)($it['dir']   ?? 'ASC')),
                    'nulls' => self::normNulls((string)($it['nulls'] ?? 'AUTO')),
                ];
            }
            return $out;
        }

        $s = \trim((string)$order);
        if ($s === '') {
            return [];
        }

        // Strip optional "ORDER BY" prefix
        $s = \preg_replace('~^\s*ORDER\s+BY\s+~i', '', $s) ?? $s;
        $s = \trim($s);
        if ($s === '') {
            return [];
        }

        $pieces = self::splitTopLevelCommas($s);
        $out    = [];

        foreach ($pieces as $raw) {
            $item = \trim($raw);
            if ($item === '') {
                continue;
            }

            $dir = 'ASC';
            $nulls = 'AUTO';

            // 1) trailing "NULLS FIRST|LAST"
            if (\preg_match('/\s+NULLS\s+(FIRST|LAST)\s*$/i', $item, $nm)) {
                $nulls = \strtoupper($nm[1]);
                $item  = \rtrim(\substr($item, 0, -\strlen($nm[0])));
            }
            // 2) trailing "ASC|DESC"
            if (\preg_match('/\s+(ASC|DESC)\s*$/i', $item, $m)) {
                $dir  = \strtoupper($m[1]);
                $item = \rtrim(\substr($item, 0, -\strlen($m[0])));
            }

            $expr = \trim(\preg_replace('/\s+/', ' ', $item) ?? $item);
            if ($expr !== '') {
                $out[] = ['expr' => $expr, 'dir' => self::normDir($dir), 'nulls' => self::normNulls($nulls)];
            }
        }
        return $out;
    }

    /* ======================== Internal helpers ======================== */

    private static function normDir(string $dir): string
    {
        $d = \strtoupper(\trim($dir));
        return ($d === 'DESC') ? 'DESC' : 'ASC';
    }

    private static function normNulls(string $nulls): string
    {
        $n = \strtoupper(\trim($nulls));
        return ($n === 'FIRST' || $n === 'LAST') ? $n : 'AUTO';
    }

    /** Try to keep PK direction aligned with the last explicit item. */
    private static function guessTieBreakerDir(array $items): ?string
    {
        if (!$items) {
            return null;
        }
        $last = \end($items);
        if (!\is_array($last)) {
            return null;
        }
        return (\strtoupper($last['dir'] ?? 'ASC') === 'DESC') ? 'DESC' : 'ASC';
    }

    /**
     * If $expr is a "bare" identifier (or quoted variant) and lacks an alias,
     * prepend "$alias." prefix. Expressions/functions/already-qualified values stay unchanged.
     */
    private static function maybePrefix(string $expr, ?string $alias): string
    {
        if ($alias === null || $alias === '') {
            return $expr;
        }
        $e = \trim($expr);

        // Bare identifier without alias
        if (\preg_match('/^[a-z_][a-z0-9_]*$/i', $e)) {
            return "{$alias}.{$e}";
        }
        // Quoted identifier without alias: "col" | `col` | [col]
        if (\preg_match('/^(?:"[^"]+"|`[^`]+`|\[[^\]]+\])$/', $e)) {
            return "{$alias}.{$e}";
        }
        // Otherwise leave as is (functions, expressions, or already aliased)
        return $expr;
    }

    /**
     * Compare an expression with the tie-breaker (case-insensitive, ignores quoting and optionally alias).
     */
    private static function exprEquals(string $expr, string $pk, ?string $alias): bool
    {
        [$ea, $ec] = self::splitAliasAndCol($expr);
        [$pa, $pc] = self::splitAliasAndCol($pk);

        if ($pc === null) {
            $pc = $pk; // PK provided only as a name
        }

        $ecn = self::normIdent($ec);
        $pcn = self::normIdent($pc);

        if ($ecn === $pcn) {
            return true;
        }

        if ($alias !== null) {
            $al = \strtolower($alias);
            if ($ea !== null && \strtolower($ea) === $al && $ecn === $pcn) {
                return true;
            }
            if ($pa !== null && \strtolower($pa) === $al && $ecn === $pcn) {
                return true;
            }
        }

        // Fully qualified match regardless of alias
        return ($ea !== null && $pa !== null && self::normIdent($ea) === self::normIdent($pa) && $ecn === $pcn);
    }

    /** @return array{0:?string,1:string} [$aliasOrNull, $col] */
    private static function splitAliasAndCol(string $s): array
    {
        $s = \trim($s);
        $dotPos = \strpos($s, '.');
        if ($dotPos === false) {
            return [null, self::stripQuotes($s)];
        }
        return [
            self::stripQuotes(\substr($s, 0, $dotPos)),
            self::stripQuotes(\substr($s, $dotPos + 1)),
        ];
    }

    private static function stripQuotes(string $id): string
    {
        $id = \trim($id);
        // "id"
        if (\strlen($id) >= 2 && $id[0] === '"' && \substr($id, -1) === '"') {
            return \substr($id, 1, -1);
        }
        // `id`
        if (\strlen($id) >= 2 && $id[0] === '`' && \substr($id, -1) === '`') {
            return \substr($id, 1, -1);
        }
        // [id]
        if (\strlen($id) >= 2 && $id[0] === '[' && \substr($id, -1) === ']') {
            return \substr($id, 1, -1);
        }
        return $id;
    }

    private static function normIdent(string $id): string
    {
        return \strtolower(self::stripQuotes($id));
    }

    private static function isPostgres(string $dialect): bool
    {
        $d = \strtolower(\trim($dialect));
        return $d === 'pgsql' || $d === 'postgres' || $d === 'postgresql';
    }

    private static function safeAlias(?string $alias): ?string
    {
        if ($alias === null) return null;
        $a = trim($alias);
        return preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $a) ? $a : null;
    }

    /**
     * Split the string into top-level items by commas.
     * Respects parentheses, quotes, backticks, and square brackets.
     *
     * @return list<string>
     */
    private static function splitTopLevelCommas(string $s): array
    {
        $out = []; $buf = ''; $depth = 0; $q = null; $len = \strlen($s);

        for ($i = 0; $i < $len; $i++) {
            $ch = $s[$i];
            $nx = $i + 1 < $len ? $s[$i + 1] : null;

            if ($q !== null) {
                $buf .= $ch;
                // Escaped quotes/backticks
                if ($q === "'" && $ch === "'" && $nx === "'") { $buf .= $nx; $i++; continue; }
                if ($q === '"' && $ch === '"' && $nx === '"') { $buf .= $nx; $i++; continue; }
                if ($q === '`' && $ch === '`' && $nx === '`') { $buf .= $nx; $i++; continue; }
                // Square brackets: ']' is escaped as ']]'
                if ($q === '[') {
                    if ($ch === ']' && $nx === ']') { $buf .= $nx; $i++; continue; }
                    if ($ch === ']') { $q = null; continue; }
                    continue;
                }
                if (in_array($q, ["'", '"', '`'], true) && $ch === $q) { $q = null; }
                continue;
            }

            if ($ch === "'" || $ch === '"' || $ch === '`' || $ch === '[') { $q = $ch; $buf .= $ch; continue; }
            if ($ch === '(') { $depth++; $buf .= $ch; continue; }
            if ($ch === ')') { $depth = \max(0, $depth - 1); $buf .= $ch; continue; }
            if ($ch === ',' && $depth === 0) { $out[] = $buf; $buf = ''; continue; }

            $buf .= $ch;
        }

        if ($buf !== '') {
            $out[] = $buf;
        }
        return \array_map('trim', $out);
    }
}
