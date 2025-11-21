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
 * Search – safe LIKE/ILIKE builder across dialects.
 *
 * Goals:
 *  - Safely escape special characters (%, _ plus escape char).
 *  - Support various search modes: contains / prefix / suffix / exact.
 *  - Case-insensitive variant without breaking indexes where possible (MySQL collations, PG ILIKE).
 *  - Optional unaccent support for PostgreSQL (requires extension + expression index).
 *  - Multi-column helper using unique placeholders (PDO + MySQL without emulation).
 *  - "Safe" variant with column whitelist and identifier quoting.
 *
 * Performance notes:
 *  - prefix (foo%) can use indexes; contains (%foo%) usually cannot.
 *  - MySQL/MariaDB: prefer CI collation (e.g. utf8mb4_0900_ai_ci) over LOWER() or indexes are unused.
 *  - PostgreSQL: ILIKE keeps indexes under case-sensitive collations; for unaccent use expression index (e.g., index on unaccent(col)).
 */
final class Search
{
    /** Escape character used for LIKE. */
    private const ESC = '\\';

    /**
     * Return proper ESCAPE clause for LIKE depending on dialect.
     * - mysql/mariadb:  ESCAPE '\\\\'   (SQL literal with two backslashes => one '\')
     * - others:        ESCAPE '\'
     */
    public static function escClause(string $dialect): string
    {
        $d = strtolower($dialect);
        if ($d === 'mysql' || $d === 'mariadb') {
            return " ESCAPE '\\\\'"; // SQL literal '\\' => one '\'
        }
        // postgres/pgsql/postgresql and others (standard)
        return " ESCAPE '\\'";
    }

    /** Simple validation for collation names (guards ciCollation). */
    private static function sanitizeCollation(string $c): string
    {
        $c = trim($c);
        if ($c === '') return '';
        if (!preg_match('~^[A-Za-z0-9_]+$~', $c)) {
            throw new \InvalidArgumentException('Invalid ciCollation name.');
        }
        return $c;
    }

    /** Restrict function name to a safe identifier (A-Z, a-z, 0-9, underscore, optional schema dot). */
    private static function sanitizeFuncName(string $f): string
    {
        $f = trim($f);
        if ($f === '') return 'unaccent';
        if (!preg_match('~^[A-Za-z0-9_\.]+$~', $f)) {
            throw new \InvalidArgumentException('Invalid function name for unaccentFn.');
        }
        return $f;
    }

    /**
     * Escape special characters for LIKE using the given ESCAPE char (default \).
     * - Escapes backslash, percent, and underscore.
     */
    public static function escapeLike(string $s): string
    {
        // Order matters – escape the ESC character first.
        return strtr($s, [
            self::ESC => self::ESC . self::ESC,
            '%'       => self::ESC . '%',
            '_'       => self::ESC . '_',
        ]);
    }

    /**
     * Build expression for a single column.
     *
     * @param string $dialect     'postgres' | 'mysql' | 'mariadb' | 'sqlite' | 'mssql' | ...
     * @param string $column      already whitelisted/quoted identifier (e.g., "t.name")
     * @param string $needle
     * @param bool   $ci          case-insensitive
     * @param array  $opts        {
     *   mode?: 'contains'|'prefix'|'suffix'|'exact',
     *   ciCollation?: string,      // MySQL/MariaDB e.g. 'utf8mb4_0900_ai_ci'
     *   useUnaccent?: bool,        // Postgres: call unaccent()
     *   unaccentFn?: string,       // Postgres: function name (default 'unaccent')
     *   emptyIsTautology?: bool,   // empty query → TRUE (default true), otherwise FALSE
     *   maxLen?: int               // limit needle length (planner guard)
     * }
     * @return array{expr:string, params:array<string,mixed>, param:mixed}
     * @phpstan-return array{expr:string, params:array<string,mixed>, param:mixed}
     */
    public static function build(string $dialect, string $column, string $needle, bool $ci = true, array $opts = []): array
    {
        $needle = self::truncate($needle, (int)($opts['maxLen'] ?? 512));
        if ($needle === '') {
            return self::emptyResult((bool)($opts['emptyIsTautology'] ?? true));
        }

        $d            = strtolower($dialect);
        $mode         = strtolower((string)($opts['mode'] ?? 'contains'));
        $useUnaccent  = (bool)($opts['useUnaccent'] ?? false);
        $unaccentFn   = self::sanitizeFuncName((string)($opts['unaccentFn'] ?? 'unaccent'));
        $ciCollation  = self::sanitizeCollation((string)($opts['ciCollation'] ?? ''));
        $esc          = self::escClause($d);

        $like   = self::pattern($needle, $mode);
        $params = [':q' => $like];

        // Optimization: exact + case-insensitive → prefer equality when a collation exists
        if ($mode === 'exact' && $ci) {
            if ($d === 'postgres') {
                // ILIKE has equivalent semantics and is simpler than = with collation
                $expr = $useUnaccent
                    ? "{$unaccentFn}({$column}) ILIKE {$unaccentFn}(:q){$esc}"
                    : "{$column} ILIKE :q{$esc}";
                return ['expr' => $expr, 'params' => $params, 'param' => $like];
            }
            if ($ciCollation !== '') {
                return [
                    'expr'   => "{$column} = :q COLLATE {$ciCollation}",
                    'params' => $params,
                    'param'  => $like,
                ];
            }
            // fallback – equality without collation would be case-sensitive; prefer LIKE/LOWER
        }

        if ($d === 'postgres') {
            if ($ci) {
                $expr = $useUnaccent
                    ? "{$unaccentFn}({$column}) ILIKE {$unaccentFn}(:q){$esc}"
                    : "{$column} ILIKE :q{$esc}";
            } else {
                $expr = "{$column} LIKE :q{$esc}";
            }
            return ['expr' => $expr, 'params' => $params, 'param' => $like];
        }

        // MySQL/MariaDB/SQLite/MSSQL/…
        if ($ci) {
            if ($ciCollation !== '') {
                // Preferred approach – typically keeps indexes usable
                return [
                    'expr'   => "{$column} LIKE :q COLLATE {$ciCollation}{$esc}",
                    'params' => $params,
                    'param'  => $like,
                ];
            }
            // Fallback – LOWER() may kill indexes; use only when CI collation unsuitable
            return [
                'expr'   => "LOWER({$column}) LIKE LOWER(:q){$esc}",
                'params' => $params,
                'param'  => $like,
            ];
        }

        return [
            'expr'   => "{$column} LIKE :q{$esc}",
            'params' => $params,
            'param'  => $like,
        ];
    }

    /**
     * Build expression for multiple columns (OR) with unique placeholders (:q0,:q1,...).
     * Useful for "search across columns".
     *
     * @param string $dialect
     * @param array<string> $columns   already whitelisted/quoted identifiers
     * @param string $needle
     * @param bool   $ci
     * @param array  $opts             same options as build()
     * @return array{expr:string, params:array<string,mixed>, param:mixed}
     * @phpstan-return array{expr:string, params:array<string,mixed>, param:mixed}
     */
    public static function buildAny(string $dialect, array $columns, string $needle, bool $ci = true, array $opts = []): array
    {
        $needle = self::truncate($needle, (int)($opts['maxLen'] ?? 512));
        if ($needle === '' || !$columns) {
            return self::emptyResult((bool)($opts['emptyIsTautology'] ?? true));
        }

        $d            = strtolower($dialect);
        $mode         = strtolower((string)($opts['mode'] ?? 'contains'));
        $useUnaccent  = (bool)($opts['useUnaccent'] ?? false);
        $unaccentFn   = self::sanitizeFuncName((string)($opts['unaccentFn'] ?? 'unaccent'));
        $ciCollation  = self::sanitizeCollation((string)($opts['ciCollation'] ?? ''));
        $esc    = self::escClause($d);
        $like   = self::pattern($needle, $mode);
        $exprs  = [];
        $params = [];
        $i      = 0;

        foreach ($columns as $c) {
            $ph          = ':q' . $i++;
            $params[$ph] = $like;

            if ($d === 'postgres') {
                if ($ci) {
                    $exprs[] = $useUnaccent
                        ? "{$unaccentFn}({$c}) ILIKE {$unaccentFn}({$ph}){$esc}"
                        : "{$c} ILIKE {$ph}{$esc}";
                } else {
                    $exprs[] = "{$c} LIKE {$ph}{$esc}";
                }
                continue;
            }

            if ($ci) {
                if ($ciCollation !== '') {
                    $exprs[] = "{$c} LIKE {$ph} COLLATE {$ciCollation}{$esc}";
                } else {
                    $exprs[] = "LOWER({$c}) LIKE LOWER({$ph}){$esc}";
                }
            } else {
                $exprs[] = "{$c} LIKE {$ph}{$esc}";
            }
        }

        return [
            'expr'   => '(' . implode(' OR ', $exprs) . ')',
            'params' => $params,
            'param'  => $like, // BC: expose the first value as well
        ];
    }

    /**
     * SAFE variant via Database: validates and quotes identifiers.
     *
     * @param Database $db
     * @param array<string> $allowedColumns  whitelist of column names (without alias), e.g. ['name','email']
     * @param string $alias                  table alias, default 't'
     * @return array{expr:string, params:array<string,mixed>, param:mixed}
     */
    public static function buildAnySafe(
        Database $db,
        string $dialect,
        array $allowedColumns,
        string $needle,
        bool $ci = true,
        array $opts = [],
        string $alias = 't'
    ): array {
        if (!$allowedColumns) {
            return ['expr' => '(1=0)', 'params' => [], 'param' => null];
        }

        // Normalize whitelist (case-insensitive) and build "alias.col"
        $seen = [];
        $cols = [];
        foreach ($allowedColumns as $c) {
            $c = (string)$c;
            if ($c === '') continue;
            $k = strtolower($c);
            if (isset($seen[$k])) continue;
            $seen[$k] = true;
            $cols[]   = \BlackCat\Database\Support\SqlIdentifier::qi($db, $alias . '.' . $c);
        }

        return self::buildAny($dialect, $cols, $needle, $ci, $opts);
    }

    /* ========================= Internal helpers ========================= */

    private static function pattern(string $needle, string $mode): string
    {
        $e = self::escapeLike($needle);
        return match ($mode) {
            'prefix' => $e . '%',
            'suffix' => '%' . $e,
            'exact'  => $e,
            default  => '%' . $e . '%', // contains
        };
    }

    /** Limit query length (defends against pathological patterns). */
    private static function truncate(string $s, int $max): string
    {
        $max = max(0, $max);
        if ($max === 0) return '';
        // multibyte-safe
        if (function_exists('mb_strlen')) {
            return mb_strlen($s) > $max ? mb_substr($s, 0, $max) : $s;
        }
        return strlen($s) > $max ? substr($s, 0, $max) : $s;
    }

    /**
     * Tautology/contradiction result for empty queries.
     * TRUE variant is useful for optional filters.
     */
    /** @phpstan-return array{expr:string, params:array<string,mixed>, param:mixed} */
    private static function emptyResult(bool $tautology): array
    {
        return [
            'expr'   => $tautology ? '(1=1)' : '(1=0)',
            'params' => [],
            'param'  => null,
        ];
    }
}
