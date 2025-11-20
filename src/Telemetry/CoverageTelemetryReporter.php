<?php
declare(strict_types=1);

namespace BlackCat\Database\Telemetry;

use BlackCat\Database\Crypto\IngressLocator;
use BlackCat\Database\Support\Observability;
use BlackCat\Database\Support\Telemetry;

final class CoverageTelemetryReporter
{
    private static bool $registered = false;
    private static $exporter = null;

    public static function register(): void
    {
        if (self::$registered) {
            return;
        }
        IngressLocator::setTelemetryCallback([self::class, 'logCoverage']);
        self::$registered = true;
    }

    public static function setExporter(?callable $exporter): void
    {
        self::$exporter = $exporter;
    }

    /**
     * @param array<int,string> $columns
     */
    public static function logCoverage(string $table, string $operation, array $columns): void
    {
        $context = [
            'table' => $table,
            'operation' => $operation,
            'columns' => $columns,
        ];
        Telemetry::info('crypto.ingress.coverage', $context);
        Observability::incrementCounter('crypto_ingress_hits', 1, [
            'table' => $table,
            'op'    => $operation,
        ]);
        CryptoCoverageCache::record($table, $operation, $columns);
        if (self::$exporter) {
            try {
                (self::$exporter)($table, $operation, $columns);
            } catch (\Throwable) {
                // exporters are best effort
            }
        }
        // TODO(telemetry): forward to VaultCoverageTracker once available.
    }
}
