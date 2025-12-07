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
use BlackCat\Database\Contracts\DatabaseIngressAdapterInterface;

/**
 * Shared helpers for generated repositories (DRY).
 *
 * Default behavior: derive the Definitions FQN from the repository FQN
 *   <Package>\Repository\<Entity>Repository -> <Package>\Definitions
 * Override {@see RepositoryHelpers::def()} in the repository if the layout differs.
 *
 * Safety & DX:
 * - Resilient to missing methods on Definitions (hasColumn/paramAliases/softDeleteColumn/versionIsNumeric).
 * - Consistently quotes identifiers via {@see SqlIdentifier::q()}.
 * - Verifies `$this->db` exists and is an instance of {@see Database}.
 * - TODO(crypto-integrations): Teach helpers to call DatabaseIngressAdapter for column
 *   transforms (encrypt/hmac/tokenize) before building SQL so repositories never inline
 *   crypto logic.
 */
trait RepositoryHelpers
{
    protected ?DatabaseIngressAdapterInterface $cryptoIngressAdapter = null;
    protected ?string $cryptoIngressTable = null;

    /**
     * Return the Definitions class FQCN for the repository.
     * Override in a concrete repository if inference is not suitable.
     *
     * @return class-string
     */
    protected function def(): string
    {
        $ns  = \preg_replace('~\\\\Repository\\\\[^\\\\]+$~', '', static::class) ?: '';
        $fqn = $ns ? ($ns . '\\Definitions') : '';

        if (\is_string($fqn) && $fqn !== '' && \class_exists($fqn)) {
            /** @var class-string $fqn */
            return $fqn;
        }

        throw new \LogicException(
            'Definitions class not found for repo ' . static::class . '. Implement protected def(): string.'
        );
    }

    /**
     * Keep only known table columns according to Definitions::hasColumn().
     *
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    protected function filterCols(array $row): array
    {
        $def = $this->def();

        // Safe fallback: if Definitions lacks hasColumn(), return the original input.
        if (!\method_exists($def, 'hasColumn')) {
            return $row;
        }

        // Blacklist generated/virtual columns to avoid inserting into computed fields (PG/MariaDB will reject).
        $generated = [];
        if (\method_exists($def, 'generatedColumns')) {
            $generated = \array_fill_keys((array)$def::generatedColumns(), true);
        }

        $out = [];
        foreach ($row as $k => $v) {
            $col = (string) $k;
            if ($col !== '' && $def::hasColumn($col) && !isset($generated[$col])) {
                $out[$col] = $v;
            }
        }
        return $this->ingressTransform($out);
    }

    /**
     * Expand input aliases and remove alias keys (see Definitions::paramAliases()).
     *
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    protected function normalizeInputRow(array $row): array
    {
        $def = $this->def();
        if (!\method_exists($def, 'paramAliases')) {
            return $row;
        }

        /** @var array<string,string> $aliases */
        $aliases = (array) $def::paramAliases();
        if (!$aliases) {
            return $row;
        }

        foreach ($aliases as $alias => $col) {
            if (\array_key_exists($alias, $row) && !\array_key_exists($col, $row)) {
                $row[$col] = $row[$alias];
            }
            unset($row[$alias]);
        }

        // Drop generated/virtual columns to avoid inserting into computed fields (PG disallows it).
        if (\method_exists($def, 'generatedColumns')) {
            foreach ((array)$def::generatedColumns() as $gen) {
                unset($row[$gen]);
            }
        }
        return $row;
    }

    /**
     * Allow services/application code to inject a manifest-aware ingress adapter.
     */
    public function setIngressAdapter(?DatabaseIngressAdapterInterface $adapter, ?string $table = null): void
    {
        $this->cryptoIngressAdapter = $adapter;
        if (\is_string($table) && $table !== '') {
            $this->cryptoIngressTable = $table;
        }
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    private function ingressTransform(array $row): array
    {
        if ($this->cryptoIngressAdapter === null || $row === []) {
            return $row;
        }

        $table = $this->cryptoIngressTable ?? $this->resolveIngressTable();
        if (!\is_string($table) || $table === '') {
            return $row;
        }

        try {
            return $this->cryptoIngressAdapter->encrypt($table, $row);
        } catch (\Throwable) {
            return $row;
        }
    }

    private function resolveIngressTable(): ?string
    {
        try {
            if (\is_string($this->cryptoIngressTable) && $this->cryptoIngressTable !== '') {
                return $this->cryptoIngressTable;
            }

            if (\method_exists($this, 'def')) {
                $fqn = $this->def();
                if (\is_string($fqn) && $fqn !== '' && \class_exists($fqn) && \method_exists($fqn, 'table')) {
                    /** @var mixed $table */
                    $table = $fqn::table();
                    return \is_string($table) && $table !== '' ? $table : null;
                }
            }
        } catch (\Throwable) {
            return null;
        }

        return null;
    }

    /** Soft-delete guard: returns SQL predicate (e.g., "t.deleted_at IS NULL") or "1=1". */
    protected function softGuard(string $alias = 't'): string
    {
        $def = $this->def();
        if (\is_string($def) && \method_exists($def, 'softDeleteColumn')) {
            /** @var string|null $col */
            $col = $def::softDeleteColumn();
            if ($col) {
                $qualified = $alias !== '' ? ($alias . '.' . $col) : $col;
                return \BlackCat\Database\Support\SqlIdentifier::qi($this->db, $qualified) . ' IS NULL';
            }
        }
        return '1=1';
    }

    /**
     * True when the version exists and is numeric (Definitions::versionIsNumeric()).
     */
    protected function isNumericVersion(): bool
    {
        $def = $this->def();
        return \method_exists($def, 'versionIsNumeric') ? (bool) $def::versionIsNumeric() : false;
    }

    /**
     * Update by PK plus extra WHERE conditions (e.g., tenant guard or business constraint).
     *
     * @param int|string|array $id          Primary key(s). For composite PK use assoc map: ['col' => val, ...].
     * @param array<string,mixed> $row      Column payload; PK columns are ignored if present.
     * @param array<string,mixed> $where    Additional (AND) conditions, col => value; NULL => IS NULL.
     * @return int                          Number of affected rows.
     */
    public function updateByIdWhere(int|string|array $id, array $row, array $where): int
    {
        $tbl = \BlackCat\Database\Support\SqlIdentifier::qi($this->db, $this->def()::table());
        $pkCols = $this->pkColumns($this->def());
        $idMap  = $this->normalizePkInput($id, $pkCols);

        $verCol = $this->def()::versionColumn();
        $updAt  = $this->def()::updatedAtColumn();

        $hasExpectedVersion = $verCol && array_key_exists($verCol, $row);
        $expectedVersion = $hasExpectedVersion ? $row[$verCol] : null;
        if ($hasExpectedVersion) unset($row[$verCol]);

        $row = $this->filterCols($this->normalizeInputRow($row));

        $params = [];
        $wherePk = $this->buildPkWhere('', $idMap, $params, 'pk_');

        // extra WHERE conditions
        $extraParts = [];
        foreach ($where as $k => $v) {
            $k = (string)$k;
            $col = \BlackCat\Database\Support\SqlIdentifier::q($this->db, $k);
            if ($v === null) {
                $extraParts[] = $col . ' IS NULL';
            } else {
                $ph = $this->uniqueParamName($params, 'w_' . $k);
                $extraParts[] = $col . ' = :' . $ph;
                $params[$ph] = $v;
            }
        }

        $assign = [];
        $pkSet = array_fill_keys($pkCols, true);
        foreach ($row as $k => $v) {
            if (isset($pkSet[$k])) continue;
            $assign[] = \BlackCat\Database\Support\SqlIdentifier::q($this->db, (string)$k) . ' = :' . $k;
            $params[$k] = $v;
        }
        $hasPayload = !empty($assign);

        // soft-delete guard
        $guard = $this->softGuard('');
        $guardSql = $guard !== '1=1' ? ' AND ' . $guard : '';

        $whereSql = $wherePk;
        if ($extraParts) { $whereSql .= ' AND ' . implode(' AND ', $extraParts); }

        // Optimistic locking branch (table has versionColumn and expected version in the payload)
        if ($verCol && $hasExpectedVersion && $hasPayload) {
            $verEsc = \BlackCat\Database\Support\SqlIdentifier::q($this->db, $verCol);
            if ($this->isNumericVersion()) $assign[] = $verEsc . ' = ' . $verEsc . ' + 1';
            if ($updAt && !array_key_exists($updAt, $row)) {
                $assign[] = \BlackCat\Database\Support\SqlIdentifier::q($this->db, $updAt) . ' = CURRENT_TIMESTAMP';
            }

            $params['expected_version'] = is_numeric($expectedVersion) ? (int)$expectedVersion : $expectedVersion;
            $sql = "UPDATE {$tbl} SET " . implode(', ', $assign)
                 . " WHERE {$whereSql}{$guardSql} AND {$verEsc} = :expected_version";
            return $this->db->execute($sql, $params);
        }

        // "Touch" mode (no payload) – bump version/updated_at when present
        if (!$hasPayload) {
            if ($verCol && $this->isNumericVersion()) {
                $assign[] = \BlackCat\Database\Support\SqlIdentifier::q($this->db, $verCol) . ' = ' . \BlackCat\Database\Support\SqlIdentifier::q($this->db, $verCol) . ' + 1';
            }
            if ($updAt) {
                $assign[] = \BlackCat\Database\Support\SqlIdentifier::q($this->db, $updAt) . ' = CURRENT_TIMESTAMP';
            }
            if (empty($assign)) return 0;
        } else {
            if ($verCol && $this->isNumericVersion()) {
                $assign[] = \BlackCat\Database\Support\SqlIdentifier::q($this->db, $verCol) . ' = ' . \BlackCat\Database\Support\SqlIdentifier::q($this->db, $verCol) . ' + 1';
            }
            if ($updAt && !array_key_exists($updAt, $row)) {
                $assign[] = \BlackCat\Database\Support\SqlIdentifier::q($this->db, $updAt) . ' = CURRENT_TIMESTAMP';
            }
        }

        $sql = "UPDATE {$tbl} SET " . implode(', ', $assign) . " WHERE {$whereSql}{$guardSql}";
        return $this->db->execute($sql, $params);
    }

    /**
     * Quick existence check by PK (respects soft-delete guard and contract view).
     */
    public function existsById(int|string|array $id): bool
    {
        $pkCols = $this->pkColumns($this->def());
        $params = [];
        $where = $this->buildPkWhere('t', $this->normalizePkInput($id, $pkCols), $params, 'pk_');
        $view = \BlackCat\Database\Support\SqlIdentifier::qi($this->db, $this->def()::contractView());
        $guard = $this->softGuard('t');
        $sql = "SELECT 1 FROM {$view} t WHERE {$where} AND {$guard} LIMIT 1";
        return (bool)$this->db->fetchOne($sql, $params);
    }

    /* ============================ Internal helpers ============================ */

    /**
     * Retrieve {@see Database} from the host class (expects property $this->db).
     */
    private function repoDb(): Database
    {
        /** @psalm-suppress RedundantCondition */
        if (!isset($this->db) || !$this->db instanceof Database) {
            throw new \LogicException(
                'RepositoryHelpers expects the host class to expose $this->db of type ' . Database::class
            );
        }
        return $this->db;
    }

    /**
     * Sanitize and uniquely name a placeholder so it follows PDO rules.
     * @param array<string,mixed> $existing
     */
    private function uniqueParamName(array $existing, string $seed): string
    {
        $base = \preg_replace('/[^A-Za-z0-9_]+/', '_', $seed) ?? '';
        $base = \trim($base, '_');
        if ($base === '' || \ctype_digit($base[0])) {
            $base = 'p_' . $base;
        }

        $name = $base;
        $i = 2;
        while (\array_key_exists($name, $existing)) {
            $name = $base . '_' . $i;
            $i++;
        }

        return $name;
    }
}
