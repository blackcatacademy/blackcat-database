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
 * Helpers for working with primary keys (including composite ones).
 *
 * Safety & DX:
 * - Validates inputs (composite PKs – positional or associative form).
 * - Strict identifier quoting via SqlIdentifier::q().
 * - Safe placeholders (sanitized names, consistent prefix).
 * - Friendly error when the host class lacks $this->db.
 *
 * Requirement: host class must have `$this->db` of type {@see Database}.
 *
 * @psalm-type PkMap = array<string,mixed>
 */
trait PkTools
{
    /**
     * Fetch PK column names from the *Definitions* class.
     * Prefers static method `pkColumns(): array`, falls back to `pk(): string`.
     *
     * @param class-string $definitionsClass
     * @return list<string>
     */
    public function pkColumns(string $definitionsClass): array
    {
        if (\method_exists($definitionsClass, 'pkColumns')) {
            $cols = (array) $definitionsClass::pkColumns();
        } elseif (\method_exists($definitionsClass, 'pk')) {
            $cols = [(string) $definitionsClass::pk()];
        } else {
            throw new \InvalidArgumentException(
                "Class {$definitionsClass} does not expose pkColumns() or pk()."
            );
        }

        // Normalize to list<string>
        $out = [];
        foreach ($cols as $c) {
            $c = (string) $c;
            if ($c === '') {
                continue;
            }
            $out[] = $c;
        }

        if (!$out) {
            throw new \InvalidArgumentException('Primary key column list is empty.');
        }
        return \array_values($out);
    }

    /**
     * Normalize the input identifier into [pkCol => value].
     * Supports:
     *  - scalar (single-column PK)
     *  - positional array [val1, val2, ...]
     *  - associative array ['col1'=>val, ...]; extra keys ignored
     *
     * @param int|string|array $id
     * @param list<string>     $pkCols
     * @return array<string,mixed>  mapped values for all PK columns (defined order)
     */
    public function normalizePkInput(int|string|array $id, array $pkCols): array
    {
        if (!$pkCols) {
            throw new \InvalidArgumentException('Cannot normalize PK – empty PK column list.');
        }

        // Single-column PK + scalar
        if (!\is_array($id)) {
            if (\count($pkCols) !== 1) {
                throw new \InvalidArgumentException('Composite PK requires a positional or associative array.');
            }
            return [$pkCols[0] => $id];
        }

        // Associative vs positional
        $isAssoc = \array_keys($id) !== \range(0, \count($id) - 1);

        if ($isAssoc) {
            $out = [];
            foreach ($pkCols as $c) {
                if (!\array_key_exists($c, $id)) {
                    throw new \InvalidArgumentException("Missing value for PK column '{$c}'.");
                }
                $out[$c] = $id[$c];
            }
            return $out;
        }

        // Positional – length must match
        if (\count($id) !== \count($pkCols)) {
            throw new \InvalidArgumentException('Number of positional values does not match PK columns.');
        }

        $out = [];
        foreach ($pkCols as $i => $c) {
            $out[$c] = $id[$i];
        }
        return $out;
    }

    /**
     * Build a WHERE expression for the PK and fill $params (placeholders without colon).
     *
     * @param string                 $alias    Table alias or empty string.
     * @param array<string,mixed>    $idMap    Output of {@see normalizePkInput()} or custom map.
     * @param array<string,mixed>    $params   Receives placeholder values.
     * @param string                 $phPrefix Placeholder prefix (e.g. "pk_").
     * @return string                          WHERE expression like "t.\"col1\" = :pk_col1 AND ..."
     */
    public function buildPkWhere(string $alias, array $idMap, array &$params, string $phPrefix = 'pk_'): string
    {
        if (!$idMap) {
            throw new \InvalidArgumentException('Cannot build WHERE – PK map is empty.');
        }

        $db    = $this->pktoolsDb();
        $parts = [];

        foreach ($idMap as $col => $val) {
            $col = (string) $col;
            if ($col === '') {
                throw new \InvalidArgumentException('Empty PK column name encountered.');
            }

            $colId = $alias !== '' ? "{$alias}.{$col}" : $col;

            // Safely quote identifier including alias.
            $quoted = SqlIdentifier::q($db, $colId);

            // Safe placeholder name (PDO variant = no colon).
            $phName = $this->pktoolsPlaceholder($phPrefix, $col);

            $parts[]           = "{$quoted} = :{$phName}";
            $params[$phName]   = $val;
        }

        return \implode(' AND ', $parts);
    }

    /**
     * Convenience wrapper over {@see buildPkWhere()} returning [sql, params].
     *
     * @param string              $alias
     * @param array<string,mixed> $idMap
     * @param string              $phPrefix
     * @return array{0:string,1:array<string,mixed>}
     */
    public function buildPkWherePair(string $alias, array $idMap, string $phPrefix = 'pk_'): array
    {
        $params = [];
        $sql    = $this->buildPkWhere($alias, $idMap, $params, $phPrefix);
        return [$sql, $params];
    }

    /* ================================ Internals ================================ */

    /**
     * Obtain Database from the host class or throw if the property is missing/wrong type.
     */
    private function pktoolsDb(): Database
    {
        /** @psalm-suppress RedundantCondition */
        if (!isset($this->db) || !$this->db instanceof Database) {
            throw new \LogicException('PkTools expects the host class to expose $this->db of type ' . Database::class);
        }
        return $this->db;
    }

    /** Safe placeholder name: `<prefix><column>` -> `[A-Za-z0-9_]+` */
    private function pktoolsPlaceholder(string $prefix, string $column): string
    {
        $p = \preg_replace('~[^A-Za-z0-9_]+~', '_', $prefix) ?? 'pk_';
        $c = \preg_replace('~[^A-Za-z0-9_]+~', '_', $column) ?? 'id';
        $name = $p . $c;

        // PDO placeholder name (without colon) must not be empty:
        if ($name === '') {
            $name = 'pk_id';
        }
        return $name;
    }
}
