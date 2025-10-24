<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use BlackCat\Core\Database;

/**
 * Generuje "minimální validní" řádky pro CRUD smoke testy podle information_schema.
 * Vyhýbá se povinným FK sloupcům – takové tabulky označí jako nebezpečné.
 */
final class RowFactory
{
    /** Vrátí [row, updatableCols, uniqueKey] nebo [null,[],[]] pokud tabulka není bezpečná. */
    public static function makeSample(string $table): array
    {
        $cols = DbHarness::columns($table);
        $fkCols = array_fill_keys(DbHarness::foreignKeyColumns($table), true);

        // pokud existuje NOT NULL FK bez defaultu -> považuj tabulku za nebezpečnou pro obecný CRUD
        foreach ($cols as $c) {
            $notNull = !$c['nullable'];
            $hasDef  = $c['col_default'] !== null;
            if ($notNull && !$hasDef && isset($fkCols[$c['name']])) {
                return [null, [], []];
            }
        }

        $row = [];
        $updatable = [];
        foreach ($cols as $c) {
            $name = $c['name'];
            if ($c['is_identity']) continue; // autoincrement/identity
            // pokud je NOT NULL bez defaultu, vymysli rozumný dummy podle typu
            $required = !$c['nullable'] && $c['col_default'] === null;
            if (!$required) continue; // necháme na defaultu/NULL

            $val = self::dummyValue($c);
            $row[$name] = $val;
            $updatable[] = $name;
        }

        // aspoň něco updatovat
        if (!$updatable) {
            // najdi první ne-PK a ne-FK a vyrob mu hodnotu
            foreach ($cols as $c) {
                if ($c['is_identity'] || isset($fkCols[$c['name']])) continue;
                $row[$c['name']] = self::dummyValue($c);
                $updatable[] = $c['name'];
                break;
            }
        }
        return [$row, $updatable, []];
    }

    public static function dummyValue(array $c): mixed
    {
        $t = strtolower((string)$c['type']);
        $full = strtolower((string)$c['full_type']);

        // MySQL enum/set
        if (str_starts_with($full, "enum(") || str_starts_with($full, "set(")) {
            if (preg_match("/'(.*?)'/", $full, $m)) { return $m[1]; }
            return 'x';
        }

        return match (true) {
            str_contains($t,'int') => 1,
            str_contains($t,'bool') || $t==='tinyint' => 1,
            str_contains($t,'json') => json_encode(['ok'=>true], JSON_UNESCAPED_SLASHES),
            str_contains($t,'double') || str_contains($t,'numeric') || str_contains($t,'real') || str_contains($t,'dec') => 1.5,
            str_contains($t,'char') || str_contains($t,'text') || $t==='uuid' || $t==='name' => 'x',
            str_contains($t,'time') || str_contains($t,'date') => (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s.u'),
            str_contains($t,'bytea') || str_contains($t,'blob') || str_contains($t,'binary') => random_bytes(4),
            default => 'x',
        };
    }
}
