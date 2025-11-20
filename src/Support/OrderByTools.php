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
use BlackCat\Database\Support\SqlIdentifier as Ident;

/**
 * OrderByTools – safe ORDER BY builder across dialects (delegates to OrderCompiler).
 *
 * Design goals:
 * - Safety: allow only whitelisted identifiers (columns or aliased names).
 * - Stability: optional tie-breaker (typically PK) ensures deterministic ordering.
 * - Ergonomics: accepts input with/without "ORDER BY" prefix; diacritics/case are ignored.
 * - Compatibility: generates "ORDER BY …" per dialect (Postgres/MySQL/MariaDB) via OrderCompiler.
 *
 * Whitelists:
 * - $allowedColumns – base table columns (without alias); automatically allow "$alias.<col>".
 * - $alsoAllowed    – aliased names ("SELECT … AS total") or explicit "alias.col" for JOINs.
 *
 * Safety notes:
 * - Functions/expressions like "SUM(...)" or "CASE..." are not allowed → give them an alias and list it in $alsoAllowed.
 * - Identifiers are always quoted via $db->quoteIdent().
 */
trait OrderByTools
{
    /** Max number of ORDER BY items (guards against pathological inputs). */
    private int $orderByMaxTerms = 8;

    /**
     * @param string        $order         User input (may include "ORDER BY" or CSV list).
     * @param array<string> $allowedColumns Whitelist of base-table columns (without alias).
     * @param Database      $db
     * @param array<string> $alsoAllowed   Allowed aliases (no dot) or explicit identifiers "alias.col".
     * @param string        $alias         Default table alias (e.g., 't').
     * @param string|null   $tiePk         Tie-breaker (typically 'id' from the base table).
     * @param bool          $stable        Whether to enforce stable ordering via tiePk.
     * @return string                       "ORDER BY …" or an empty string.
     */
    private function buildOrderBy(
        string $order,
        array $allowedColumns,
        Database $db,
        array $alsoAllowed = [],
        string $alias = 't',
        ?string $tiePk = null,
        bool $stable = true
    ): string {
        $raw = \trim($order);
        if ($raw === '') {
            return '';
        }

        // Remove optional "ORDER BY" prefix
        $raw = \preg_replace('~^\s*ORDER\s+BY\s+~i', '', $raw) ?? $raw;
        $raw = \trim($raw);
        if ($raw === '') {
            return '';
        }

        // Normalize whitelists
        $allowCols = \array_fill_keys(\array_map('strtolower', $allowedColumns), true); // 'id' => true
        $allowFull = [];                                                                 // 't.id' nebo 'u.created_at' => true
        $aliasL    = \strtolower($alias);

        foreach (\array_keys($allowCols) as $c) {
            $allowFull[$aliasL . '.' . $c] = true; // base alias
        }

        foreach ($alsoAllowed as $x) {
            $xL = \strtolower(\trim($x));
            if ($xL === '') {
                continue;
            }
            if (\str_contains($xL, '.')) {
                // explicitly allowed "alias.col"
                $allowFull[$xL] = true;
            } else {
                // aliased column
                $allowCols[$xL] = true;
            }
        }

        // Tokenize items (CSV). Limit the count for safety.
        $parts = \array_map('trim', \explode(',', $raw));
        if (\count($parts) > $this->orderByMaxTerms) {
            $parts = \array_slice($parts, 0, $this->orderByMaxTerms);
        }

        $items = [];
        $seen  = [];

        foreach ($parts as $p) {
            if ($p === '') {
                continue;
            }

            // Strict syntax: (<ident> | <alias>.<ident>) [ASC|DESC] [NULLS FIRST|LAST]
            if (!\preg_match(
                '~^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)' .
                '(?:\s+(ASC|DESC))?' .
                '(?:\s+NULLS\s+(FIRST|LAST))?$~i',
                $p,
                $m
            )) {
                // ignore invalid tokens to stay resilient
                continue;
            }

            $ident = $m[1];
            $dir   = \strtoupper($m[2] ?? 'ASC');
            $nulls = \strtoupper($m[3] ?? 'AUTO');

            // Validace whitelistem
            $identL    = \strtolower($ident);
            $aliasPart = null;
            $colOnly   = $identL;

            if (\str_contains($identL, '.')) {
                [$aliasPart, $colOnly] = \explode('.', $identL, 2);
            }

            $ok = false;
            if ($aliasPart === null) {
                // Without alias: must exist in allowCols (uses $alias)
                $ok = isset($allowCols[$colOnly]);
            } else {
                // With alias: (a) base alias + allowCols, (b) explicitly whitelisted alias.col
                if ($aliasPart === $aliasL && isset($allowCols[$colOnly])) {
                    $ok = true;
                } elseif (isset($allowFull[$aliasPart . '.' . $colOnly])) {
                    $ok = true;
                }
            }

            if (!$ok) {
                continue;
            }

            // Deduplicate identical expression+direction+NULLS
            $dedupKey = \strtolower(($aliasPart ? $aliasPart . '.' : '') . $colOnly . ' ' . $dir . ' ' . $nulls);
            if (isset($seen[$dedupKey])) {
                continue;
            }
            $seen[$dedupKey] = true;

            // Build the quoted expression
            if ($aliasPart !== null) {
                // Preserve original casing, qualify safely via Ident::qi()
                [$a, $c] = \explode('.', $ident, 2);
                $expr = Ident::qi($db, $a . '.' . $c);
            } else {
                // Simple/aliased identifier via Ident::q()
                $expr = Ident::q($db, $ident); // may be "id" or alias "total"
            }

            $items[] = ['expr' => $expr, 'dir' => $dir, 'nulls' => $nulls];
        }

        if (!$items) {
            return '';
        }

        // Tie-breaker: if none provided and the base table has 'id', use 't.id'
        if ($tiePk === null && isset($allowCols['id'])) {
            $tiePk = 'id';
        }

        $dialect = $db->isPg() ? 'postgres' : ($db->isMysql() ? 'mysql' : 'generic');

        // Expressions are already quoted – OrderCompiler must not add more prefixes/aliases.
        // items, dialect, tableAlias(null), tieBreakerExpr, stable
        $tieExpr = $tiePk ? Ident::qi($db, $alias . '.' . $tiePk) : null;
        $result  = OrderCompiler::compile($items, $dialect, null, $tieExpr, $stable);
        // Output must be empty or "ORDER BY …"
        return \ltrim($result);
    }
}
