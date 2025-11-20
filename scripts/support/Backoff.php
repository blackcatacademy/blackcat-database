<?php
declare(strict_types=1);

final class Backoff
{
    public static function withRetry(callable $fn, int $maxAttempts = 5, int $baseMs = 50, int $capMs = 2000, int $maxTotalMs = 15000) {
        $attempt = 0; $start = microtime(true);
        start:
        try { return $fn($attempt+1); }
        catch (\Throwable $e) {
            $attempt++;
            if ($attempt >= $maxAttempts || ((microtime(true)-$start)*1000) >= $maxTotalMs) { throw $e; }
            $sleep = min($capMs, (int)($baseMs * (1 << ($attempt-1))));
            usleep(random_int((int)($sleep*0.5), $sleep) * 1000);
            goto start;
        }
    }
}
