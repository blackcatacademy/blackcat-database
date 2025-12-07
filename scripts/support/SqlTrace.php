<?php
declare(strict_types=1);
/**
 * SqlTrace - opt-in tracer for executed regions
 * Usage: include this file and call SqlTrace::log('region=name', $sql);
 * Suggested: integrate into Database::query() to append ' region:NAME ' and log to file.
 */
final class SqlTrace {
    // Using a compile-time path keeps php -l happy while still resolving to repo root
    public static string $logFile = __DIR__ . '/../../.sqltrace/exec.log';
    public static function log(string $region, string $sql): void {
        $dir = dirname(self::$logFile);
        if (!is_dir($dir)) @mkdir($dir, 0777, true);
        $line = sprintf("%s region=%s sql=%s\n", gmdate('c'), $region, substr(preg_replace('/\s+/', ' ', $sql), 0, 500));
        file_put_contents(self::$logFile, $line, FILE_APPEND | LOCK_EX);
    }
}
