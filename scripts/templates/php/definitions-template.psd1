@{
  File   = 'src/Definitions.php'
  Tokens = @(
    'NAMESPACE','TABLE','VIEW','COLUMNS_ARRAY','PK','SOFT_DELETE_COLUMN',
    'UPDATED_AT_COLUMN','VERSION_COLUMN','DEFAULT_ORDER_CLAUSE',
    'UNIQUE_KEYS_ARRAY','JSON_COLUMNS_ARRAY'
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
    public static function pk(): string { return '[[PK]]'; }

    // --- volitelná metadata (mohou být prázdná) ---
    public static function softDeleteColumn(): ?string {
        $c = '[[SOFT_DELETE_COLUMN]]'; return $c !== '' ? $c : null;
    }
    public static function updatedAtColumn(): ?string {
        $c = '[[UPDATED_AT_COLUMN]]'; return $c !== '' ? $c : null;
    }
    public static function versionColumn(): ?string {
        $c = '[[VERSION_COLUMN]]'; return $c !== '' ? $c : null; // pro optimistic locking
    }
    /** např. "created_at DESC, id DESC" */
    public static function defaultOrder(): ?string {
        $c = '[[DEFAULT_ORDER_CLAUSE]]'; return $c !== '' ? $c : null;
    }
    /** @return array<int,array<int,string>> seznam unikátních klíčů (sloupcových kombinací) */
    public static function uniqueKeys(): array { return [[UNIQUE_KEYS_ARRAY]]; }
    /** @return string[] JSON sloupce kvůli castům/operacím */
    public static function jsonColumns(): array { return [[JSON_COLUMNS_ARRAY]]; }

    // --- pomocníci ---
    public static function hasColumn(string $col): bool {
        static $set = null;
        if ($set === null) { $set = array_fill_keys(self::columns(), true); }
        return isset($set[$col]);
    }
}
'@
}
