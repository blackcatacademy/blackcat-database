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
 * JsonFilters – safe generator of JSON expressions for SQL (PostgreSQL/MySQL/MariaDB).
 *
 * Goals:
 * - Every output is **parameterized** (no value interpolation into SQL).
 * - Dialect differences are abstracted (PG jsonb @>, MySQL/MariaDB JSON_CONTAINS).
 * - Robust path handling: supports `a.b.c`, `/a/b/c`, and PG array literals `{"a","b","c"}`.
 * - JSON encoding is delegated to JsonCodec (stable flags, UTF-8 handling).
 *
 * Note: the `column` parameter expects an already safe identifier/column (ideally
 * via a whitelist and any quoting outside of this helper).
 */
final class JsonFilters
{
    /**
     * JSON contains
     * - PG:  (col)::jsonb @> :needle::jsonb
     * - MySQL/MariaDB: JSON_CONTAINS(col, :needle)
     *
     * @return array{expr:string,param:string}
     */
    public static function contains(string $dialect, string $column, array $needle): array
    {
        $json = self::encodeJson($needle);
        $d = self::normalizeDialect($dialect);

        if ($d === 'postgres') {
            // Safe even for json columns (cast to jsonb).
            return ['expr' => "({$column})::jsonb @> :needle::jsonb", 'param' => $json];
        }

        // MySQL/MariaDB: JSON_CONTAINS(document, candidate)
        return ['expr' => "JSON_CONTAINS({$column}, :needle)", 'param' => $json];
    }

    /**
     * JSON -> text at the provided path (dialect-compatible expression).
     * - PG:  (col)::jsonb #>> (:jpath)::text[]
     *        (where :jpath is a PG array literal e.g. {"a","b","c"})
     * - MySQL/MariaDB: JSON_UNQUOTE(JSON_EXTRACT(col, :jpath))
     *        (where :jpath is a JSON path e.g. $.a.b.c, properly quoted for "weird" keys)
     *
     * @return array{expr:string,param:string}
     */
    public static function getText(string $dialect, string $column, string $path): array
    {
        $d = self::normalizeDialect($dialect);

        if ($d === 'postgres') {
            // #>> expects text[]; provide the parameter as a text PG array literal and cast it.
            $pgPathArray = self::toPgTextArrayLiteral($path);
            return ['expr' => "({$column})::jsonb #>> (:jpath)::text[]", 'param' => $pgPathArray];
        }

        // MySQL/MariaDB: JSON path with proper key quoting
        $jsonPath = self::toMySqlJsonPath($path);
        return ['expr' => "JSON_UNQUOTE(JSON_EXTRACT({$column}, :jpath))", 'param' => $jsonPath];
    }

    /* ===================== Internal helpers ===================== */

    private static function normalizeDialect(string $dialect): string
    {
        $d = \strtolower(\trim($dialect));
        if ($d === 'postgresql') $d = 'postgres';
        if ($d === 'mariadb')    $d = 'mysql';
        return $d;
    }

    private static function encodeJson(array $v): string
    {
        // Use JsonCodec for stable behavior (UTF-8, zero fraction, etc.)
        $json = JsonCodec::encode($v);
        return $json ?? 'null';
    }

    /**
     * Accepts "a.b.c" / "/a/b/c" / "{a,b,c}" / "{""weird,key"","x"}" → PG array literal {"a","b","c"}
     * with proper escaping.
     */
    private static function toPgTextArrayLiteral(string $path): string
    {
        $parts = self::splitPath($path);
        $quoted = \array_map([self::class, 'pgArrayElem'], $parts);
        return '{' . \implode(',', $quoted) . '}';
    }

    private static function pgArrayElem(string $s): string
    {
        // Escape \ and " ; quote when necessary.
        $needsQuotes = \preg_match('/[,\s{}"]/u', $s) === 1 || $s === '';
        $esc = \str_replace(['\\', '"'], ['\\\\', '\\"'], $s);
        return $needsQuotes ? '"' . $esc . '"' : $esc;
    }

    /**
     * Reasonable path splitting:
     * - "a.b.c"          → ["a","b","c"]
     * - "/a/b/c"         → ["a","b","c"]
     * - "{a,b,c}"        → ["a","b","c"]
     * - "{\"weird,key\",\"x\"}" → ["weird,key","x"]
     * - "$.a.b" / "$"    → ["a","b"] / []
     */
    private static function splitPath(string $path): array
    {
        $p = \trim($path);
        if ($p === '' || $p === '{}' || $p === '$' || $p === '$.') {
            return [];
        }

        // PG array literal
        if ($p[0] === '{' && \str_ends_with($p, '}')) {
            $body = \substr($p, 1, -1);
            if ($body === '') return [];
            $out = [];
            $cur = '';
            $q = false;
            for ($i = 0, $n = \strlen($body); $i < $n; $i++) {
                $ch = $body[$i];
                if ($q) {
                    if ($ch === '\\' && $i + 1 < $n) { $cur .= $body[$i + 1]; $i++; continue; }
                    if ($ch === '"') { $q = false; continue; }
                    $cur .= $ch; continue;
                }
                if ($ch === '"') { $q = true; continue; }
                if ($ch === ',') { $out[] = $cur; $cur = ''; continue; }
                $cur .= $ch;
            }
            $out[] = $cur;
            // Drop empty segments
            return \array_values(\array_filter($out, static fn($s) => $s !== ''));
        }

        // /a/b/c
        if ($p[0] === '/') {
            $p = \trim($p, '/');
            return $p === '' ? [] : (\preg_split('~/+~', $p) ?: []);
        }

        // a.b.c nebo $.a.b
        $p = \ltrim($p, '$.');
        if ($p === '') return [];
        return \preg_split('/\.+/', $p) ?: [];
    }

    /**
     * MySQL JSON path builder with proper quoting of keys and indexes.
     * Output always starts with '$'.
     * - $.foo.bar
     * - $."key.with.dots"
     * - $[0].items[2]
     */
    private static function toMySqlJsonPath(string $path): string
    {
        $parts = self::splitPath($path);
        $out = '$';
        foreach ($parts as $part) {
            if ($part === '') continue;

            // Pure numeric index → array element
            if (\ctype_digit($part)) {
                $out .= '[' . (string)\intval($part, 10) . ']';
                continue;
            }

            // Simple identifier that does not need quoting
            if (\preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $part) === 1) {
                $out .= '.' . $part;
            } else {
                // uvozovky a backslash escapujeme dle JSON path pravidel
                $esc = \str_replace(['\\', '"'], ['\\\\', '\\"'], $part);
                $out .= '."' . $esc . '"';
            }
        }
        return $out;
    }
}
