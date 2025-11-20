<?php
declare(strict_types=1);

namespace BlackCat\Database\Telemetry;

/**
 * Lightweight in-memory cache for crypto ingress coverage events.
 * Intended for debugging/CLI tooling – not a persistent metric store.
 */
final class CryptoCoverageCache
{
    /** @var array<string,int> */
    private static array $counts = [];

    /** @var array<int,array{table:string,operation:string,columns:array<string>}> */
    private static array $recent = [];

    private const MAX_RECENT = 50;

    /**
     * @param array<int,string> $columns
     */
    public static function record(string $table, string $operation, array $columns): void
    {
        $key = $table . ':' . $operation;
        self::$counts[$key] = (self::$counts[$key] ?? 0) + 1;

        self::$recent[] = [
            'table'     => $table,
            'operation' => $operation,
            'columns'   => array_values($columns),
        ];

        if (\count(self::$recent) > self::MAX_RECENT) {
            \array_shift(self::$recent);
        }
    }

    /**
     * @return array<string,int>
     */
    public static function counts(): array
    {
        \ksort(self::$counts);
        return self::$counts;
    }

    /**
     * @return array<int,array{table:string,operation:string,columns:array<string>}>
     */
    public static function recent(): array
    {
        return self::$recent;
    }

    public static function reset(): void
    {
        self::$counts = [];
        self::$recent = [];
    }
}
