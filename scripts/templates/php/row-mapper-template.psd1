@{
  File   = 'src/Mapper/[[DTO_CLASS]]Mapper.php'
  Tokens = @(
    'NAMESPACE',                # např. BlackCat\Database\Packages\Users
    'DTO_CLASS',                # např. UserDto
    'COLUMNS_TO_PROPS_MAP',     # např. @{ id='id'; email_hash='emailHash'; created_at='createdAt' } -> ve skriptu převést na PHP array
    'BOOL_COLUMNS_ARRAY',       # např. ['is_active','is_locked']
    'INT_COLUMNS_ARRAY',        # např. ['id','failed_logins']
    'FLOAT_COLUMNS_ARRAY',      # např. ['total','tax_total']
    'JSON_COLUMNS_ARRAY',       # např. ['meta','encryption_meta']
    'DATE_COLUMNS_ARRAY',       # např. ['created_at','updated_at','deleted_at','last_login_at']
    'BINARY_COLUMNS_ARRAY',     # např. ['token_hash','ip_hash']
    'NULLABLE_COLUMNS_ARRAY',   # např. ['deleted_at','last_login_at',...]
    'TIMEZONE'                  # např. 'UTC' (nebo 'Europe/Prague')
  )
  Content = @'
<?php
declare(strict_types=1);

namespace [[NAMESPACE]]\Mapper;

use [[NAMESPACE]]\Dto\[[DTO_CLASS]];
use DateTimeImmutable;
use DateTimeZone;
use RuntimeException;

/**
 * Obousměrný mapovač řádek DB <-> DTO:
 * - bezpečné casty dle whitelistů sloupců (bool/int/float/json/date/binary)
 * - mapování názvů sloupců na vlastnosti DTO (COLUMNS_TO_PROPS_MAP)
 * - tolerantní k chybějícím sloupcům (ponechá null)
 */
final class [[DTO_CLASS]]Mapper
{
    /** @var array<string,string> */
    private const COL_TO_PROP = [[COLUMNS_TO_PROPS_MAP]];
    /** @var string[] */
    private const BOOL_COLS   = [[BOOL_COLUMNS_ARRAY]];
    /** @var string[] */
    private const INT_COLS    = [[INT_COLUMNS_ARRAY]];
    /** @var string[] */
    private const FLOAT_COLS  = [[FLOAT_COLUMNS_ARRAY]];
    /** @var string[] */
    private const JSON_COLS   = [[JSON_COLUMNS_ARRAY]];
    /** @var string[] */
    private const DATE_COLS   = [[DATE_COLUMNS_ARRAY]];
    /** @var string[] */
    private const BIN_COLS    = [[BINARY_COLUMNS_ARRAY]];
    /** @var string[] */
    private const NULLABLE    = [[NULLABLE_COLUMNS_ARRAY]];
    private const TZ          = '[[TIMEZONE]]';

    private static function isNullable(string $col): bool {
        static $set = null;
        if ($set === null) { $set = array_fill_keys(self::NULLABLE, true); }
        return isset($set[$col]);
    }

    private static function colToProp(string $col): string {
        return self::COL_TO_PROP[$col] ?? $col; // fallback 1:1
    }
    private static function propToCol(string $prop): string {
        static $rev = null;
        if ($rev === null) { $rev = array_flip(self::COL_TO_PROP); }
        return $rev[$prop] ?? $prop;
    }

    private static function toBool(mixed $v): bool {
        // MySQL TINYINT(1) / Postgres boolean / stringy "0"/"1"
        return match (true) {
            $v === null => false,
            is_bool($v) => $v,
            is_int($v)  => $v !== 0,
            is_string($v) => $v !== '' && $v !== '0',
            default => (bool)$v,
        };
    }
    private static function toInt(mixed $v): ?int {
        if ($v === null || $v === '') return null;
        return (int)$v;
    }
    private static function toFloat(mixed $v): ?float {
        if ($v === null || $v === '') return null;
        return (float)$v;
    }
    private static function toJson(mixed $v): mixed {
        if ($v === null || $v === '') return null;
        if (is_array($v) || is_object($v)) return $v;
        $decoded = json_decode((string)$v, true, 512, JSON_THROW_ON_ERROR);
        return $decoded;
    }
    private static function toDate(mixed $v): ?DateTimeImmutable {
        if ($v === null || $v === '') return null;
        $tz = new DateTimeZone(self::TZ);
        if ($v instanceof DateTimeImmutable) return $v->setTimezone($tz);
        return new DateTimeImmutable((string)$v, $tz);
    }

    /**
     * Hydratuje DTO z řádku (sloupce -> vlastnosti + casty).
     */
    public static function fromRow(array $row): [[DTO_CLASS]] {
        $vals = [];

        foreach ($row as $col => $val) {
            $prop = self::colToProp((string)$col);

            if (in_array($col, self::BOOL_COLS, true))   { $val = self::toBool($val); }
            elseif (in_array($col, self::INT_COLS, true))   { $val = self::toInt($val); }
            elseif (in_array($col, self::FLOAT_COLS, true)) { $val = self::toFloat($val); }
            elseif (in_array($col, self::JSON_COLS, true))  { $val = self::toJson($val); }
            elseif (in_array($col, self::DATE_COLS, true))  { $val = self::toDate($val); }
            // BIN_COLS ponecháváme jako raw string/resource (DB driver-dependent)

            if ($val === null && !self::isNullable($col)) {
                // Nevyhazujeme výjimku – neznáme kontext (insert/update). Ponecháme null.
            }
            $vals[$prop] = $val;
        }

        // Vlastnosti DTO, které v řádku nebyly, ponecháme jako null (pokud konstruktor vyžaduje non-null, generátor zajistí default param)
        // Konstrukci provedeme reflexivně: generátor předá parametry ve správném pořadí přes named arguments (PHP 8.1+)
        // Pro jednoduchost poskládáme z mapy COL_TO_PROP i fallbacků:
        return new [[DTO_CLASS]](...$vals);
    }

    /**
     * Mapuje DTO zpět na asociativní řádek pro DB (insert/update).
     * - JSON sloupce se enkódují JSONem.
     * - DATETIME se formátuje na 'Y-m-d H:i:s.u' (MySQL DATETIME(6) / PG timestamptz).
     * - bool -> 0/1 (kvůli MySQL).
     */
    public static function toRow([[DTO_CLASS]] $dto, ?array $onlyProps = null): array {
        $out = [];
        $src = $dto->toArray(); // public readonly -> bezpečné

        if ($onlyProps !== null) {
            $src = array_intersect_key($src, array_fill_keys($onlyProps, true));
        }

        foreach ($src as $prop => $val) {
            $col = self::propToCol((string)$prop);

            if (in_array($col, self::JSON_COLS, true)) {
                $val = $val === null ? null : json_encode($val, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR);
            } elseif (in_array($col, self::DATE_COLS, true)) {
                if ($val instanceof DateTimeImmutable) {
                    $val = $val->format('Y-m-d H:i:s.u');
                } elseif ($val !== null && $val !== '') {
                    $val = (new DateTimeImmutable((string)$val, new DateTimeZone(self::TZ)))->format('Y-m-d H:i:s.u');
                } else {
                    $val = null;
                }
            } elseif (in_array($col, self::BOOL_COLS, true)) {
                $val = $val === null ? null : ($val ? 1 : 0);
            } elseif (in_array($col, self::INT_COLS, true)) {
                $val = $val === null ? null : (int)$val;
            } elseif (in_array($col, self::FLOAT_COLS, true)) {
                $val = $val === null ? null : (float)$val;
            }
            // BIN_COLS ponecháváme beze změny

            $out[$col] = $val;
        }
        return $out;
    }

    /** Batch varianta: mapuje pole řádků na pole DTO. */
    public static function hydrateList(array $rows): array {
        $out = [];
        foreach ($rows as $r) { $out[] = self::fromRow($r); }
        return $out;
    }
}
'@
}
