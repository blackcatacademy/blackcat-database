@{
  File   = 'src/Definitions.php'
  Tokens = @(
    'NAMESPACE','TABLE','VIEW','COLUMNS_ARRAY','PK','SOFT_DELETE_COLUMN',
    'UPDATED_AT_COLUMN','VERSION_COLUMN','DEFAULT_ORDER_CLAUSE',
    'UNIQUE_KEYS_ARRAY','JSON_COLUMNS_ARRAY','PK_STRATEGY','IS_ROWLOCK_SAFE',
    'INT_COLUMNS_ARRAY','PARAM_ALIASES_ARRAY'
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]];

final class Definitions {
    // --- základní metadata ---
    public static function table(): string { return '[[TABLE]]'; }
    public static function contractView(): string { return '[[VIEW]]'; }
    /** @return string[] */
    public static function columns(): array { return [[COLUMNS_ARRAY]]; }

    /**
     * Primární klíč(e) tabulky. Podporuje jednoduché i složené PK.
     * [[PK]] může být "id" nebo "col1, col2".
     * @return string[]
     */
    public static function pkColumns(): array {
        $raw = '[[PK]]';
        // povol formát "a,b" i s mezerami
        $parts = array_values(array_filter(array_map(
            static fn($p) => trim($p, " \t\n\r\0\x0B`\""),
            preg_split('/\s*,\s*/', $raw ?? '')
        )));
        if (!$parts) { return [$raw]; }
        return $parts;
    }
    /** Zpětná kompatibilita: první sloupec z PK. */
    public static function pk(): string { return self::pkColumns()[0]; }

    // --- volitelná metadata ---
    public static function softDeleteColumn(): ?string {
        $c = '[[SOFT_DELETE_COLUMN]]'; return $c !== '' ? $c : null;
    }
    public static function updatedAtColumn(): ?string {
        $c = '[[UPDATED_AT_COLUMN]]'; return $c !== '' ? $c : null;
    }
    public static function versionColumn(): ?string {
        $c = '[[VERSION_COLUMN]]'; return $c !== '' ? $c : null;
    }
    /** např. "created_at DESC, id DESC" */
    public static function defaultOrder(): ?string {
        $c = '[[DEFAULT_ORDER_CLAUSE]]'; return $c !== '' ? $c : null;
    }

    /** @return array<int,array<int,string>> seznam unikátních klíčů */
    public static function uniqueKeys(): array { return [[UNIQUE_KEYS_ARRAY]]; }

    /** @return string[] JSON sloupce kvůli castům/operacím */
    public static function jsonColumns(): array { return [[JSON_COLUMNS_ARRAY]]; }

    /** @return string[] Seznam číselných sloupců (heuristika z generátoru; bez runtime DB dotazů). */
    public static function intColumns(): array { return [[INT_COLUMNS_ARRAY]]; }

    /** @return array<string,string> alias => column (pro normalizaci vstupů) */
    public static function paramAliases(): array { return [[PARAM_ALIASES_ARRAY]]; }

    /** Hint pro repo: je sloupec s verzí opravdu číselný? (bez information_schema) */
    public static function versionIsNumeric(): bool
    {
        $v = self::versionColumn();
        return $v !== null && in_array($v, self::intColumns(), true);
    }

    // --- pomocníci ---
    public static function hasColumn(string $col): bool {
        static $set = null;
        if ($set === null) { $set = array_fill_keys(self::columns(), true); }
        return isset($set[$col]);
    }

    /**
     * identity | uuid | natural | composite
     */
    public static function pkStrategy(): string {
        $c = '[[PK_STRATEGY]]';
        return $c !== '' ? $c : 'natural';
    }

    public static function isIdentityPk(): bool {
        return self::pkStrategy() === 'identity';
    }

    /** True, pokud je tabulka vhodná pro testy row-locků (bez kaskád/FK, malá šíře řádku apod.). */
    public static function isRowLockSafe(): bool {
        return [[IS_ROWLOCK_SAFE]];
    }

    /** Pohodlný alias – má tabulka verzi pro optimistic locking? */
    public static function supportsOptimisticLocking(): bool {
        return self::versionColumn() !== null;
    }

    /** Pro JSON casty/operace – rychlý test bez vytváření setu. */
    public static function hasJsonColumn(string $col): bool {
        static $set = null;
        if ($set === null) { $set = array_fill_keys(self::jsonColumns(), true); }
        return isset($set[$col]);
    }

    public static function isSoftDeleteEnabled(): bool { return self::softDeleteColumn() !== null; }
}
'@
}
