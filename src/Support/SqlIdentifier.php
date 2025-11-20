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
 * SqlIdentifier – safe and convenient quoting of SQL identifiers.
 *
 * Goals:
 * - Unified quoting via Database::quoteIdent() (dialect-aware).
 * - Support for qualified names (schema.table, alias.col, …).
 * - Safe handling of the asterisk (*) and "t.*".
 * - Small helpers for common scenarios (lists, qualification, table.*).
 *
 * Note: assumes inputs are identifiers (not arbitrary expressions).
 *       If you pass expressions, use SqlExpr instead.
 */
final class SqlIdentifier
{
    /** Operators/patterns that look more like expressions than identifiers. */
    private const EXPR_PATTERN = '/[\s()\'"\[\]{}+*%|&^=<>!:;,@]|--|\/\*|\*\/|::|->>?|#>?>?/';

    /**
     * Safely quote an identifier (supports "a.b.c").
     * - Quotes each part via Database::quoteIdent().
     * - Leaves the asterisk without quotes (returns '*', or '"t".*' when qualified).
     * - Ignores empty segments.
     */
    public static function qi(Database $db, string $ident): string
    {
        $ident = trim($ident);
        if ($ident === '') {
            throw new \InvalidArgumentException('Empty identifier.');
        }
        if ($ident === '*') {
            return '*';
        }

        // Split by dots but skip empty parts (protects against "schema..table").
        $parts = preg_split('/\s*\.\s*/', $ident, -1, \PREG_SPLIT_NO_EMPTY) ?: [];
        $out   = [];

        foreach ($parts as $p) {
            $p = trim(self::stripQuotes($p));
            if ($p === '') {
                continue;
            }
            if ($p === '*') {
                $out[] = '*';
            } else {
                // Light sanitization: allow anything without whitespace/expression tokens.
                if (!self::isTokenSafeEnough($p)) {
                    throw new \InvalidArgumentException('Suspicious identifier part: ' . $p);
                }
                $out[] = $db->quoteIdent($p);
            }
        }

       if (!$out) {
            // Better to fail than quote something like "." or similar artifacts.
            throw new \InvalidArgumentException('Invalid identifier: ' . $ident);
        }
        return implode('.', $out);
    }

    /**
     * Quote a single identifier; if "t.col" (or multi-dot) arrives, delegate to qi().
     * - '*' is left without quotes.
     */
    public static function q(Database $db, string $ident): string
    {
        $ident = trim($ident);
        if ($ident === '*') {
            return '*';
        }
        if (str_contains($ident, '.')) {
            return self::qi($db, $ident);
        }
        $bare = self::stripQuotes($ident);
        if (!self::isTokenSafeEnough($bare)) {
            throw new \InvalidArgumentException('Suspicious identifier: ' . $ident);
        }
        return $db->quoteIdent($bare);
    }

    /**
     * Return a qualified identifier with an alias if the identifier is not already qualified.
     * - If $alias is empty or $ident already contains a dot, only q()/qi() is used.
     * - If $ident looks like an expression (whitespace/parens), the alias is NOT added and q()/qi() is used.
     */
    public static function qualify(Database $db, string $ident, ?string $alias): string
    {
        $ident = trim($ident);
        $alias = $alias !== null ? trim($alias) : null;

        // If it looks like an expression, return as-is (caller should use SqlExpr).
        if (self::looksLikeExpression($ident)) {
            return $ident;
        }

        if ($ident === '*' || $alias === null || $alias === '' || str_contains($ident, '.')) {
            return self::q($db, $ident);
        }
        return self::qi($db, $alias . '.' . $ident);
    }

    /**
     * If it's an expression, return unchanged; otherwise qualify with the alias when appropriate.
     */
    public static function qualifyOrExpr(Database $db, string $s, ?string $alias): string
    {
        return self::looksLikeExpression($s) ? $s : self::qualify($db, $s, $alias);
    }

    /**
     * Safely create "table.*" (or "schema"."table".*).
     */
    public static function tableStar(Database $db, string $tableOrAlias): string
    {
        $left = self::qi($db, $tableOrAlias);
        return $left . '.*';
    }

    /**
     * Quote a list of identifiers via q()/qi() and join them with $sep.
     * @param array<int,string> $idents
     */
    public static function qList(Database $db, array $idents, string $sep = ', '): string
    {
        $out = [];
        foreach ($idents as $i) {
            $out[] = self::q($db, $i);
        }
        return implode($sep, $out);
    }

    /**
     * Simple check for a "bare" identifier (without dots or quotes).
     */
    public static function isBare(string $ident): bool
    {
        return (bool)preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $ident);
    }

    /* ============================ internals ============================ */

    /**
     * Remove wrapping quotes/backticks/brackets for more robust handling of unexpected input.
     * Does not deal with more complex cases like "schema"."table" (assumes unquoted parts with dots).
     */
    private static function stripQuotes(string $id): string
    {
        $s = trim($id);
        $n = strlen($s);
        if ($n >= 2) {
            // "col"
            if ($s[0] === '"' && $s[$n - 1] === '"') {
                return substr($s, 1, -1);
            }
            // `col`
            if ($s[0] === '`' && $s[$n - 1] === '`') {
                return substr($s, 1, -1);
            }
            // [col]
            if ($s[0] === '[' && $s[$n - 1] === ']') {
                return substr($s, 1, -1);
            }
        }
        return $s;
    }

    /**
     * Heuristic: does it look like an expression (whitespace, parentheses, operators)?
     * If so, do not add an alias (qualify); just pass it through q()/qi().
     */
    private static function looksLikeExpression(string $s): bool
    {
        return (bool)preg_match(self::EXPR_PATTERN, $s);
     }

    /** Light sanitization of a single identifier part (no dots, no wrapping quotes). */
    private static function isTokenSafeEnough(string $s): bool
    {
        if ($s === '' || $s === '*') return $s === '*';     // empty disallowed, asterisk only explicitly
        // Must not look like an expression – whitespace, comments, casts, JSON/CITUS operators, etc.
        if (preg_match(self::EXPR_PATTERN, $s)) return false;
        return true;
    }

    /** Syntactic helper: quote both parts for "ident AS alias". */
    public static function qAs(Database $db, string $ident, string $alias): string
    {
        return self::q($db, $ident) . ' AS ' . self::q($db, $alias);
    }
}
