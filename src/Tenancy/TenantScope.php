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

namespace BlackCat\Database\Tenancy;

use BlackCat\Core\Database;
use BlackCat\Database\Support\Criteria as BaseCriteria;

/**
 * TenantScope – safe and convenient helper for multi/single-tenant filters.
 */
final class TenantScope
{
    /** @var int|string|array<int|string> */
    private int|string|array $tenant;

    /**
     * @param int|string|array<int|string> $tenantId
     */
    public function __construct(int|string|array $tenantId)
    {
        $this->tenant = is_array($tenantId) ? array_values($tenantId) : $tenantId;
    }

    /** @return list<int|string> */
    public function idList(): array
    {
        return is_array($this->tenant) ? $this->tenant : [$this->tenant];
    }

    /** Direct integration with the shared Criteria abstraction. */
    public function apply(BaseCriteria $c, string $column = 'tenant_id'): void
    {
        $c->tenant($this->tenant, $column);
    }

    /**
     * Returns a raw SQL fragment and parameters when Criteria is not available.
     *
     * @return array{expr:string, params:array<string,mixed>}
     */
    public function sql(string $dialect, string $column = 'tenant_id', string $paramBase = '__tenant'): array
    {
        $paramBase = $this->sanitizeParamBase($paramBase);

        if (is_array($this->tenant)) {
            if (!$this->tenant) return ['expr' => '1=0', 'params' => []];
            $ph = [];
            $params = [];
            foreach ($this->tenant as $i => $v) {
                $name = ':' . $paramBase . '_' . $i;
                $ph[] = $name;
                $params[$name] = $v;
            }
            return ['expr' => sprintf('%s IN (%s)', $column, implode(',', $ph)), 'params' => $params];
        }

        return ['expr' => "{$column} = :{$paramBase}", 'params' => [':'.$paramBase => $this->tenant]];
    }

    /**
     * Safe variant that quotes identifiers (recommended).
     *
     * @return array{expr:string, params:array<string,mixed>}
     */
    public function sqlSafe(Database $db, string $column = 'tenant_id', string $paramBase = '__tenant'): array
    {
        $paramBase = $this->sanitizeParamBase($paramBase);
        $colExpr   = $this->quoteColumn($db, $column);

        if (is_array($this->tenant)) {
            if (!$this->tenant) return ['expr' => '1=0', 'params' => []];
            $ph = [];
            $params = [];
            foreach ($this->tenant as $i => $v) {
                $name = ':' . $paramBase . '_' . $i;
                $ph[] = $name;
                $params[$name] = $v;
            }
            return ['expr' => "{$colExpr} IN (".implode(',', $ph).')', 'params' => $params];
        }

        return ['expr' => "{$colExpr} = :{$paramBase}", 'params' => [':'.$paramBase => $this->tenant]];
    }

    /**
     * Appends the tenant filter to an SQL statement (detects WHERE vs AND).
     *
     * @param array<string,mixed> $paramsInOut merged/updated parameter bag
     */
    public function appendToWhere(string $sql, array &$paramsInOut, Database $db, string $column = 'tenant_id', string $paramBase = '__tenant'): string
    {
        $piece = $this->sqlSafe($db, $column, $paramBase);
        $hasWhere = (bool)preg_match('/\bwhere\b/i', $sql);
        $sql .= $hasWhere ? ' AND ' . $piece['expr'] : ' WHERE ' . $piece['expr'];
        $paramsInOut = $piece['params'] + $paramsInOut; // tenant params first to avoid accidental overwrite
        return $sql;
    }

    /**
     * Validates that an incoming row belongs to this tenant scope.
     * Throws \LogicException when the row targets a different tenant.
     */
    public function guardRow(array $row, string $column = 'tenant_id'): void
    {
        $val = $row[$column] ?? null;
        if ($val === null) {
            throw new \LogicException("Missing '{$column}' for tenant-scoped write.");
        }
        if (!in_array($val, $this->idList(), true)) {
            throw new \LogicException("Tenant mismatch on '{$column}': {$val}");
        }
    }

    /** True if the tenant value is allowed in the current scope. */
    public function isAllowed(int|string $tenantId): bool
    {
        return in_array($tenantId, $this->idList(), true);
    }

    /**
     * Ensures tenant_id is present when writing data.
     * For single-tenant scope the column is auto-filled; multi-tenant scopes require explicit values.
     *
     * @return array<string,mixed>
     */
    public function attach(array $row, string $column = 'tenant_id'): array
    {
        if (array_key_exists($column, $row)) {
            $this->guardRow($row, $column);
            return $row;
        }
        $ids = $this->idList();
        if (count($ids) !== 1) {
            throw new \LogicException("Ambiguous tenant: cannot auto-attach '{$column}' for multiple tenants.");
        }
        $row[$column] = $ids[0];
        return $row;
    }

    /**
     * Bulk variant of {@see attach()}.
     *
     * @param list<array<string,mixed>> $rows
     * @return list<array<string,mixed>>
     */
    public function attachMany(array $rows, string $column = 'tenant_id'): array
    {
        $out = [];
        foreach ($rows as $r) {
            $out[] = $this->attach($r, $column);
        }
        return $out;
    }

    /** Validates a list of tenant IDs during bulk operations. */
    public function guardIds(array $ids): void
    {
        foreach ($ids as $t) {
            if (!in_array($t, $this->idList(), true)) {
                throw new \LogicException("Tenant mismatch on id list: {$t}");
            }
        }
    }

    // ---------------- Internal helpers ----------------

    private function quoteColumn(Database $db, string $column): string
    {
        // Supports alias.column notation (e.g. "t.tenant_id")
        if (str_contains($column, '.')) {
            [$a, $c] = explode('.', $column, 2);
            return \BlackCat\Database\Support\SqlIdentifier::qi($db, $a . '.' . $c);
        }
        return \BlackCat\Database\Support\SqlIdentifier::q($db, $column);
    }

    private function sanitizeParamBase(string $base): string
    {
        $s = preg_replace('~[^A-Za-z0-9_]+~', '_', $base) ?? '_p';
        return $s === '' ? '_p' : $s;
    }

    /** Convenience suffix for unique placeholder namespaces (e.g. when multiple scopes join). */
    public function paramBaseSuffix(string $base, string|int $suffix): string
    {
        return $this->sanitizeParamBase($base . '_' . (string)$suffix);
    }
}
