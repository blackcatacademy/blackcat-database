<?php
declare(strict_types=1);

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;

/**
 * Bezpečné skládání ORDER BY napříč dialekty s delegací do OrderCompileru.
 *
 * Použití (zpětně kompatibilní):
 *   $orderSql = $this->buildOrderBy($order, Definitions::columns(), $this->db);
 *   ... " WHERE $where $orderSql LIMIT $limit OFFSET $offset"
 */
trait OrderByTools
{
    /**
     * @param string        $order           Např. "created_at DESC, id"
     * @param array<string> $allowedColumns  Whitelist sloupců (Definitions::columns())
     * @param Database      $db              Kvůli quoteIdent() a detekci dialektu
     * @param array<string> $alsoAllowed     Volitelně: aliasy z JOINů/SELECTu (např. "category_name")
     * @param string        $alias           Alias základní tabulky/view (výchozí 't')
     * @param string|null   $tiePk           Tie-breaker (např. 'id'); necháš-li null, zkusí 'id', pokud je ve whitelistu
     * @param bool          $stable          Přidat tie-breaker, pokud chybí v ORDER BY
     * @return string "ORDER BY …" nebo prázdný string
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
        $raw = trim($order);
        if ($raw === '') return '';

        // Odstřihni případné "ORDER BY"
        $raw = preg_replace('~^\s*ORDER\s+BY\s+~i', '', $raw) ?? $raw;
        if ($raw === '') return '';

        // Whitelist (sloupce z tabulky + volitelné aliasy z JOINů/SELECTu)
        $allow = array_fill_keys(array_map('strtolower', $allowedColumns), true);
        foreach ($alsoAllowed as $x) { $allow[strtolower($x)] = true; }

        $items = [];
        $seen  = [];

        foreach (array_map('trim', explode(',', $raw)) as $p) {
            if ($p === '') continue;

            // ident (col | t.col) [ASC|DESC] [NULLS FIRST|LAST]
            if (!preg_match(
                '~^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)' .
                '(?:\s+(ASC|DESC))?' .
                '(?:\s+NULLS\s+(FIRST|LAST))?$~i',
                $p, $m
            )) {
                continue; // neznámý/nesafe tvar
            }

            $ident = $m[1];                           // "col" nebo "t.col"
            $dir   = strtoupper($m[2] ?? 'ASC');
            $nulls = strtoupper($m[3] ?? 'AUTO');     // AUTO = bez explicitního NULLS

            // Validace proti whitelistu: stripni případný alias
            $lower   = strtolower($ident);
            $colOnly = str_contains($lower, '.') ? explode('.', $lower, 2)[1] : $lower;
            if (!isset($allow[$colOnly])) continue;

            // Dedup (case-insensitive, včetně NULLS)
            $dedupKey = strtolower($ident.' '.$dir.' '.$nulls);
            if (isset($seen[$dedupKey])) continue;
            $seen[$dedupKey] = true;

            // Bezpečné ocitování identifikátoru (umí "t.col")
            if (str_contains($ident, '.')) {
                [$a, $c] = explode('.', $ident, 2);
                $expr = $db->quoteIdent($a) . '.' . $db->quoteIdent($c);
            } else {
                // aliasované výrazy z SELECTu (např. category_name) — citujeme jako jediný ident
                $expr = $db->quoteIdent($ident);
            }

            $items[] = ['expr' => $expr, 'dir' => $dir, 'nulls' => $nulls];
        }

        if (!$items) return '';

        // Tie-breaker (stabilní řazení)
        if ($tiePk === null && isset($allow['id'])) {
            $tiePk = 'id';
        }
        $tiePkExpr = null;
        if ($tiePk !== null) {
            if (str_contains($tiePk, '.')) {
                [$a, $c] = explode('.', $tiePk, 2);
                $tiePkExpr = $db->quoteIdent($a) . '.' . $db->quoteIdent($c);
            } else {
                // preferuj plně kvalifikované "t.pk"
                $tiePkExpr = $db->quoteIdent($alias) . '.' . $db->quoteIdent($tiePk);
            }
        }

        // Dialekt pro OrderCompiler
        $dialect = $db->isPg() ? 'postgres' : ($db->isMysql() ? 'mysql' : 'generic');

        // Do kompilátoru posíláme už OCITOVANÉ výrazy, proto alias v parametru = null (ať nic nepřidává).
        $sql = OrderCompiler::compile($items, $dialect, null, $tiePkExpr, $stable);

        // OrderCompiler vrací " ORDER BY …" s úvodní mezerou → sjednotíme tvar na "ORDER BY …"
        return ltrim($sql);
    }
}
