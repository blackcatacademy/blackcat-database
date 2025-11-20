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

use BlackCat\Database\SqlDialect;

final class SqlSplitter
{
    /**
     * Split the script into individual statements while respecting DELIMITER,
     * comments (--, #, /* * /), strings, backticks, and PG dollar-quoted literals.
     * @return list<string>
     */
    public static function split(string $sql, SqlDialect $dialect): array
    {
        $out = [];
        $buf = '';

        // Strip UTF-8 BOM if present
        if (strncmp($sql, "\xEF\xBB\xBF", 3) === 0) {
            $sql = substr($sql, 3);
        }

        $len = strlen($sql);

        // Dialect shortcuts
        $isMysql = $dialect->isMysql();
        $isPg    = $dialect->isPg();

        $inSingle   = false;   // '...'
        $inDouble   = false;   // "..."
        $inBacktick = false;   // `...`
        $inDollar   = false;   // $tag$...$tag$
        $dollarTag  = '';

        $inLineComment  = false; // -- ... \n
        $inHashComment  = false; // #  ... \n (MySQL)
        $inBlockComment = false; // /* ... */

        $delimiter = ';';
        $i = 0;

        // Helper: is the char at position $i escaped (odd number of backslashes to the left)?
        $isEscaped = static function (string $s, int $pos) use ($isMysql): bool {
            // Postgres (and the SQL standard) does not use \ as an escape in strings (outside E''/settings),
            // so treat "\'" as non-escaping to avoid blocking the string terminator.
            if (!$isMysql || $pos <= 0) {
                return false;
            }
            $j = $pos - 1; $slashes = 0;
            while ($j >= 0 && $s[$j] === '\\') { $slashes++; $j--; }
            return ($slashes % 2) === 1;
        };

        while ($i < $len) {
            // DELIMITER (only when outside strings/dollar/comments) at current position
            if (!$inSingle && !$inDouble && !$inBacktick && !$inDollar && !$inLineComment && !$inHashComment && !$inBlockComment) {
                if ($isMysql && preg_match('~\G\s*DELIMITER\s+(\S+)~Ai', $sql, $m, 0, $i)) {
                    $delimiter = $m[1];
                    // Skip to end of line
                    $nl = strpos($sql, "\n", $i);
                    $i = $nl === false ? $len : $nl + 1;
                    continue;
                }
            }

            $ch   = $sql[$i];
            $next = ($i + 1 < $len) ? $sql[$i + 1] : '';

            /* ---------------- PG dollar-quoted ---------------- */
            if (!$inSingle && !$inDouble && !$inBacktick && !$inLineComment && !$inHashComment && !$inBlockComment) {
                if (!$inDollar && $ch === '$') {
                    if (preg_match('~\G\$([A-Za-z0-9_]*)\$~A', $sql, $m, 0, $i)) {
                        $inDollar = true; $dollarTag = $m[1];
                        $buf .= $m[0]; $i += strlen($m[0]);
                        continue;
                    }
                } elseif ($inDollar) {
                    $endTag = '$' . $dollarTag . '$';
                    if (substr($sql, $i, strlen($endTag)) === $endTag) {
                        $buf .= $endTag; $i += strlen($endTag);
                        $inDollar = false; $dollarTag = '';
                        continue;
                    }
                    $buf .= $ch; $i++; continue;
                }
            }

            /* ---------------- comments ---------------- */
            // Enter comments only when outside strings/backticks/dollar/comments
            if (!$inSingle && !$inDouble && !$inBacktick && !$inDollar) {
                if (!$inLineComment && !$inHashComment && !$inBlockComment) {
                    // -- ... (SQL standard; MySQL requires --␣ but we accept both forms for robustness)
                    if ($ch === '-' && $next === '-') {
                        $inLineComment = true;
                        $buf .= $ch . $next; $i += 2;
                        continue;
                    }
                    // # ... (MySQL)
                    if ($isMysql && $ch === '#') {
                        $inHashComment = true;
                        $buf .= $ch; $i++;
                        continue;
                    }
                    // /* ... */
                    if ($ch === '/' && $next === '*') {
                        $inBlockComment = true;
                        $buf .= '/*'; $i += 2;
                        continue;
                    }
                } else {
                    // Inside comments copy characters and look for the terminator
                    if ($inLineComment) {
                        $buf .= $ch; $i++;
                        if ($ch === "\n" || $ch === "\r") { $inLineComment = false; }
                        continue;
                    }
                    if ($inHashComment) {
                        $buf .= $ch; $i++;
                        if ($ch === "\n" || $ch === "\r") { $inHashComment = false; }
                        continue;
                    }
                    if ($inBlockComment) {
                        if ($ch === '*' && $next === '/') {
                            $buf .= '*/'; $i += 2; $inBlockComment = false; continue;
                        }
                        $buf .= $ch; $i++; continue;
                    }
                }
            }

            /* ---------------- strings / identifiers ---------------- */
            if ($inSingle) {
                // SQL standard: '' inside a string
                if ($ch === "'" && $next === "'") { $buf .= "''"; $i += 2; continue; }
                $buf .= $ch; $i++;
                if ($ch === "'" && !$isEscaped($sql, $i - 1)) { $inSingle = false; }
                continue;
            }
            if ($inDouble) {
                // Identifier: "" inside
                if ($ch === '"' && $next === '"') { $buf .= '""'; $i += 2; continue; }
                $buf .= $ch; $i++;
                if ($ch === '"' && !$isEscaped($sql, $i - 1)) { $inDouble = false; }
                continue;
            }
            if ($isMysql && $inBacktick) {
                // MySQL identifier: `` inside
                if ($ch === '`' && $next === '`') { $buf .= '``'; $i += 2; continue; }
                $buf .= $ch; $i++;
                if ($ch === '`') { $inBacktick = false; }
                continue;
            }

            // Opening strings / identifiers
            if ($ch === "'") { $inSingle = true;   $buf .= $ch; $i++; continue; }
            if ($ch === '"') { $inDouble = true;   $buf .= $ch; $i++; continue; }
            if ($isMysql && $ch === '`') { $inBacktick = true; $buf .= $ch; $i++; continue; }

            /* ---------------- statement end ---------------- */
            if ($delimiter === ';') {
                if ($ch === ';') {
                    $trim = trim($buf);
                    if ($trim !== '') $out[] = $trim;
                    $buf = ''; $i++; continue;
                }
            } else {
                if ($delimiter !== '' && substr($sql, $i, strlen($delimiter)) === $delimiter) {
                    $trim = trim($buf);
                    if ($trim !== '') $out[] = $trim;
                    $buf = ''; $i += strlen($delimiter); continue;
                }
            }

            /* ---------------- regular character ---------------- */
            $buf .= $ch; $i++;
        }

        $trim = trim($buf);
        if ($trim !== '') $out[] = $trim;
        return $out;
    }
}
