<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

/**
 * Generuje minimálně validní řádky:
 * - povinné (NOT NULL bez defaultu) FK řeší rekurzí (rodiče přes Repository),
 * - ostatní povinné sloupce = deterministický dummy (nikdy null),
 * - VŽDY doplní sloupce PRVNÍHO dostupného unique key (Definitions ∪ Schema) omezeného na povolené sloupce.
 */
final class RowFactory
{
    private const MAX_DEPTH = 8;

    /**
     * @param array $overrides možnost předepsat hodnoty (např. ['user_id'=>123])
     * @return array{0:?array,1:array<int,string>,2:array<int,string>}
     */
    public static function makeSample(string $table, array $overrides = []): array
    {
        $cols = DbHarness::columns($table);
        if (!$cols) return [null, [], []];

        // 1) Safe režim (řeší povinné FK)
        try {
            [$row, $upd, $uk] = self::buildRow($table, $overrides, 0, []);
            if ($row !== null) {
                $byName = self::indexByName($cols);
                $uk = self::ensureFirstResolvedUniqueFilled($table, $byName, $row) ?: $uk;
                // ořízni na allowed columns (repo filter)
                $row = array_intersect_key($row, array_fill_keys(DbHarness::allowedColumns($table), true));
                return [$row, $upd, $uk];
            }
        } catch (\Throwable $_) {}

        // 2) Fallback – jen ne-FK required + doplnit unique key
        $fkCols = array_map('strtolower', DbHarness::foreignKeyColumns($table));
        $fkSet  = array_fill_keys($fkCols, true);
        $allowedSet = array_fill_keys(DbHarness::allowedColumns($table), true);

        $row = []; $updatable = [];
        foreach ($cols as $c) {
            $name = (string)$c['name'];
            $nameLc = strtolower($name);
            if (!empty($c['is_identity'])) continue;

            if (self::isRequired($c) && !isset($fkSet[$nameLc]) && isset($allowedSet[$name])) {
                $row[$name] = self::dummyValue($c);
            }

            $isDatetime = (bool)preg_match('/(date|time)/i', (string)($c['type'] ?? ''));
            if (!preg_match('/^(id|'.preg_quote(DbHarness::primaryKey($table),'/').'|created_at|updated_at|deleted_at)$/', $name)
                && !$isDatetime) {
                $updatable[] = $name;
            }
        }

        $byName = self::indexByName($cols);
        $uk = self::ensureFirstResolvedUniqueFilled($table, $byName, $row);
        $row = array_intersect_key($row, $allowedSet); // jistota
        return [$row, array_values(array_unique($updatable)), $uk ?? []];
    }

    /** Rekurzivní konstrukce vložitelného řádku včetně povinných FK parentů. */
    private static function buildRow(string $table, array $overrides, int $depth, array $stack): array
    {
        if ($depth > self::MAX_DEPTH) return [null, [], []];
        if (in_array($table, $stack, true)) return [null, [], []];

        $cols = DbHarness::columns($table);
        if (!$cols) return [null, [], []];

        $byName = self::indexByName($cols);
        $allowedSet = array_fill_keys(DbHarness::allowedColumns($table), true);
        $row = [];

        // 1) povinné FK (single-column). Multi-column povinné → fail (raději než hádat).
        $fks = DbHarness::foreignKeysDetailed($table);
        foreach ($fks as $fk) {
            $local   = $fk['cols'];
            $refT    = $fk['ref_table'];
            $refCols = $fk['ref_cols'];

            if (count($local) !== 1 || count($refCols) !== 1) {
                $allRequired = true;
                foreach ($local as $lc) {
                    $meta = $byName[strtolower($lc)] ?? null;
                    if (!$meta || !self::isRequired($meta)) { $allRequired = false; break; }
                }
                if ($allRequired) return [null, [], []];
                continue;
            }

            $lc = $local[0];
            $meta = $byName[strtolower($lc)] ?? null;
            if (!$meta) continue;

            if (array_key_exists($lc, $overrides)) {
                if (isset($allowedSet[$lc])) $row[$lc] = $overrides[$lc];
                continue;
            }

            if (self::isRequired($meta)) {
                [$parentRow] = self::buildRow($refT, [], $depth + 1, array_merge($stack, [$table]));
                if ($parentRow === null) return [null, [], []];

                $ins = DbHarness::insertAndReturnId($refT, $parentRow);
                if ($ins === null) return [null, [], []];

                if (isset($allowedSet[$lc])) $row[$lc] = $ins['pk'];
            }
        }

        // 2) doplň ostatní povinné ne-FK sloupce (bez identity)
        for ($i=0, $n=count($cols); $i<$n; $i++) {
            $c = $cols[$i];
            $name = (string)$c['name'];
            if (!self::isRequired($c)) continue;
            if (!empty($c['is_identity'])) continue;
            if (array_key_exists($name, $row)) continue;
            if (!isset($allowedSet[$name])) continue;

            if (array_key_exists($name, $overrides)) {
                $row[$name] = $overrides[$name];
            } else {
                $row[$name] = self::dummyValue($c);
            }
        }

        // 3) updatable
        $pk  = DbHarness::primaryKey($table);
        $upd = [];
        foreach ($cols as $c) {
            $n = (string)$c['name'];
            $isDatetime = (bool)preg_match('/(date|time)/i', (string)($c['type'] ?? ''));
            if (!preg_match('/^('.preg_quote($pk,'/').'|id|created_at|updated_at|deleted_at)$/', $n) && !$isDatetime) {
                $upd[] = $n;
            }
        }

        // 4) doplň PRVNÍ resolved unique key
        $uk = self::ensureFirstResolvedUniqueFilled($table, $byName, $row) ?? [];

        return [$row, array_values(array_unique($upd)), $uk];
    }

    /** Vrátí true pokud je sloupec NOT NULL bez defaultu. */
    private static function isRequired(array $col): bool
    {
        $notNull = !(bool)($col['nullable'] ?? true);
        $hasDef  = array_key_exists('col_default', $col) && $col['col_default'] !== null;
        return $notNull && !$hasDef;
    }

    /** index [lower(name) => meta] */
    private static function indexByName(array $cols): array
    {
        $by = [];
        foreach ($cols as $c) $by[strtolower((string)$c['name'])] = $c;
        return $by;
    }

    /**
     * Doplň do $row všechny sloupce PRVNÍHO resolved unique key (Definitions ∪ Schema),
     * který JE podmnožinou allowedColumns. Vrací seznam sloupců nebo null.
     */
    private static function ensureFirstResolvedUniqueFilled(string $table, array $colsByName, array &$row): ?array
    {
        $allowedSet = array_fill_keys(DbHarness::allowedColumns($table), true);
        foreach (DbHarness::resolvedUniqueKeys($table) as $uk) {
            if (!$uk) continue;
            // musí být subset allowed
            $subset = true;
            foreach ($uk as $c) { if (!isset($allowedSet[$c])) { $subset = false; break; } }
            if (!$subset) continue;

            foreach ($uk as $c) {
                if (!array_key_exists($c, $row)) {
                    $meta = $colsByName[strtolower($c)] ?? ['name'=>$c,'type'=>'text','full_type'=>'text','nullable'=>true,'is_identity'=>false];
                    $row[$c] = self::dummyValue($meta);
                }
            }
            return $uk;
        }
        return null;
    }

    /**
     * Deterministická „rozumná“ hodnota dle typu (nikdy null).
     * - Pro *_id vybírá správný typ (int/string/uuid).
     */
    public static function dummyValue(array $c): mixed
    {
        $name   = trim((string)($c['name'] ?? ''));
        $nameLc = strtolower($name);
        $type   = strtolower(trim((string)($c['type'] ?? '')));
        $full   = strtolower(trim((string)($c['full_type'] ?? $type)));
        static $seq = 1;

        // *_id / id – vždy ne-NULL a typově správné
        if (preg_match('/(^id$|_id$)/i', $nameLc)) {
            if (str_contains($type, 'uuid')) {
                $n = str_pad((string)$seq++, 12, '0', STR_PAD_LEFT);
                return "00000000-0000-4000-8000-" . substr($n, -12);
            }
            if (preg_match('/(char|text|name|varchar)/', $type)) return '1';
            return 1;
        }

        // name-based datetime
        if (preg_match('/(^|_)(created|updated|deleted|processed|verified|expires|expiry|valid|paid|refunded|locked|scheduled|published|completed|available|sent|received)(_|$)at$/', $nameLc)
            || preg_match('/(_on|_time|_date|^date_|^time_|_until|_expiry|_expires)$/', $nameLc)) {
            return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s');
        }

        // ENUM/SET
        if (preg_match('/^(enum|set)\((.+)\)$/i', $full, $m)) {
            $raw = $m[2];
            if (preg_match_all("/'((?:\\\\'|[^'])*)'/", $raw, $mm)) {
                $vals = array_map(fn($s)=>str_replace("\\'", "'", $s), $mm[1]);
                if ($vals) return $vals[0];
            }
        }

        // BINARY
        if (preg_match('/\b(var)?binary\((\d+)\)/i', $full, $m)) {
            $n = (int)$m[2]; return random_bytes(max(1, $n));
        }
        if (preg_match('/\bblob\b/', $type)) { return random_bytes(16); }

        // Heuristiky názvů
        if ($name === 'currency') return 'USD';
        if ($name === 'iso2')     return 'US';
        if ($name === 'iso3')     return 'USA';
        if (preg_match('/slug$/', $name)) { return 't-'.bin2hex(random_bytes(6)).'-'.$seq++; }

        // CHAR/VARCHAR(n)
        if (preg_match('/\b(char|varchar)\((\d+)\)/i', $full, $m)) {
            $n = (int)$m[2];
            if (preg_match('/(hash|token|signature)$/', $nameLc)) {
                $hex = bin2hex(random_bytes(intdiv($n + 1, 2)));
                return substr($hex, 0, $n);
            }
            return substr('t-'.$seq++, 0, max(1, $n));
        }

        // hashe/tokény bez velikosti
        if (preg_match('/(hash|token|signature)$/', $nameLc)) {
            $target = match ($nameLc) {
                'password_hash' => 60,
                'ip_hash'       => 32,
                default         => 32,
            };
            $hex = bin2hex(random_bytes(intdiv($target + 1, 2)));
            return substr($hex, 0, $target);
        }

        if (preg_match('/^(email|email_address)$/', $name)) {
            return 'john.doe.'.$seq++.'@example.test';
        }
        if (preg_match('/(_ms|_sec|_count|_qty|_attempts|_number|_total|_amount)$/', $name)) {
            return '1'; // DECIMAL/NUMERIC bezpečně jako string
        }
        if (preg_match('/^(status|state)$/', $name)) {
            return 'new';
        }

        // Typové heuristiky
        if (str_contains($type, 'json')) {
            return '{}';
        }
        if (preg_match('/(date|time)/', $type)) {
            return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s');
        }
        if (preg_match('/(int|serial|year)/', $type)) {
            return 1;
        }
        if (preg_match('/(decimal|numeric|double|float|real)/', $type)) {
            return '1.00';
        }
        if (preg_match('/(char|text|uuid|name)/', $type)) {
            return 't-'.$seq++;
        }
        if (preg_match('/(bool|tinyint\(1\))/', $type)) {
            return 1;
        }

        return 'x'; // nikdy null
    }

    /**
     * Volitelný helper: vytvoří vzorek a rovnou vloží do DB, vrátí PK.
     * @return array{row:array, pkCol:string, pk:mixed}
     */
    public static function insertSample(string $table, array $overrides = []): array
    {
        [$row] = self::makeSample($table, $overrides);
        if ($row === null) {
            throw new \RuntimeException("Cannot construct safe sample row for '$table'");
        }
        $ins = DbHarness::insertAndReturnId($table, $row);
        if ($ins === null) {
            throw new \RuntimeException("Insert succeeded but PK could not be determined for '$table'");
        }
        return ['row' => $row, 'pkCol' => $ins['pkCol'], 'pk' => $ins['pk']];
    }
}
