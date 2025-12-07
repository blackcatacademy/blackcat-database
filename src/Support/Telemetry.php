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

/**
 * Tiny opt-in telemetry facade.
 * - accepts any PSR-3 logger via setLogger($logger) without hard type-hints
 * - emits debug/info/notice/warning/error/critical/alert/emergency best-effort
 * - supports default context + min level threshold + safe context normalization
 * - TODO(crypto-integrations): feed DatabaseIngressAdapter coverage counters here so DB
 *   services can export encryption metrics (encrypted_rows_total, plaintext_rejected_total).
 */
final class Telemetry
{
    private static ?object $logger = null;

    /** Default context merged into every log call */
    private static array $defaults = [];

    /** If set, messages below this level are dropped (PSR-3 levels) */
    private static ?int $minWeight = null;

    /** @param object|null $logger Expected to implement Psr\Log\LoggerInterface */
    public static function setLogger(?object $logger): void
    {
        self::$logger = $logger;
    }

    /** Overwrite defaults (merge per-call stays possible via $context+) */
    public static function setDefaultContext(array $context): void
    {
        self::$defaults = $context;
    }

    /** Set minimum accepted level (e.g. 'info','warning','error'); null = no filter */
    public static function setMinLevel(?string $level): void
    {
        self::$minWeight = $level !== null ? self::weight($level) : null;
    }

    private static function call(string $level, string $message, array $context = []): void
    {
        try {
            $lvl = strtolower($level);
            if (self::$minWeight !== null && self::weight($lvl) < self::$minWeight) {
                return;
            }

            $ctx = self::normalizeContext(self::$defaults + $context);

            if (self::$logger && \method_exists(self::$logger, $lvl)) {
                self::$logger->{$lvl}($message, $ctx);
            } elseif (self::$logger && \method_exists(self::$logger, 'log')) {
                self::$logger->log($lvl, $message, $ctx);
            }
        } catch (\Throwable) {
            // Best-effort: never propagate exceptions
        }
    }

    /** Map PSR-3 level to numeric weight for thresholding. */
    private static function weight(string $level): int
    {
        static $map = [
            'debug'     => 100,
            'info'      => 200,
            'notice'    => 250,
            'warning'   => 300,
            'error'     => 400,
            'critical'  => 500,
            'alert'     => 550,
            'emergency' => 600,
        ];
        return $map[strtolower($level)] ?? 0;
    }

    /** Make context safe & compact for typical PSR-3 implementations. */
    private static function normalizeContext(array $ctx): array
    {
        $norm = static function ($v) use (&$norm) {
            if ($v instanceof \DateTimeInterface) return $v->format(DATE_ATOM);
            if ($v instanceof \JsonSerializable)  return $v->jsonSerialize();
            if (is_array($v)) {
                $o = [];
                foreach ($v as $k => $vv) { $o[$k] = $norm($vv); }
                return $o;
            }
            if (is_object($v)) {
                if (method_exists($v, '__toString')) return (string)$v;
                return 'object(' . (new \ReflectionClass($v))->getName() . ')';
            }
            if (is_resource($v)) return 'resource';
            return $v;
        };

        foreach ($ctx as $k => $v) {
            $ctx[$k] = $norm($v);
        }
        return $ctx;
    }

    /**
     * Extracts safe diagnostic fields from a Throwable (including PDO info).
     *
     * @return array<string,mixed>
     */
    public static function errorFields(\Throwable $e, int $depth = 0): array
    {
        $fields = [
            'class' => (new \ReflectionClass($e))->getName(),
            'message' => $e->getMessage(),
        ];
        $fields['code'] = $e->getCode();

        $pdoSrc = $e instanceof \PDOException ? $e : ($e->getPrevious() instanceof \PDOException ? $e->getPrevious() : null);
        if ($pdoSrc instanceof \PDOException) {
            $ei = $pdoSrc->errorInfo;
            if (is_array($ei)) {
                $sqlState = $ei[0] ?? null;
                $driverCode = $ei[1] ?? null;
                $driverMsg = $ei[2] ?? null;
                if ($sqlState) {
                    $fields['sqlstate'] = (string)$sqlState;
                }
                if ($driverCode !== null) {
                    $fields['driver_code'] = (int)$driverCode;
                }
                if ($driverMsg) {
                    $fields['driver_message'] = (string)$driverMsg;
                }
            }
        }

        $prev = $e->getPrevious();
        if ($prev && $depth < 3) {
            $fields['cause'] = self::errorFields($prev, $depth + 1);
        }

        return $fields;
    }

    /**
     * Probabilistic sampling helper driven by `sample` value in context (0..1).
     */
    public static function shouldSample(array $context): bool
    {
        $rate = $context['sample'] ?? 1.0;
        if (!is_numeric($rate)) {
            return true;
        }

        $ratio = max(0.0, min(1.0, (float)$rate));
        if ($ratio <= 0.0) {
            return false;
        }
        if ($ratio >= 1.0) {
            return true;
        }

        $max = (float)PHP_INT_MAX;
        $roll = random_int(0, PHP_INT_MAX) / $max;
        return $roll <= $ratio;
    }

    // Convenience methods (PSR-3 levels)
    public static function debug(string $m, array $c = []): void { self::call('debug', $m, $c); }
    public static function info(string $m, array $c = []): void  { self::call('info', $m, $c); }
    public static function notice(string $m, array $c = []): void { self::call('notice', $m, $c); }
    public static function warn(string $m, array $c = []): void  { self::call('warning', $m, $c); } // alias
    public static function warning(string $m, array $c = []): void { self::call('warning', $m, $c); }
    public static function error(string $m, array $c = []): void { self::call('error', $m, $c); }
    public static function critical(string $m, array $c = []): void { self::call('critical', $m, $c); }
    public static function alert(string $m, array $c = []): void { self::call('alert', $m, $c); }
    public static function emergency(string $m, array $c = []): void { self::call('emergency', $m, $c); }
}
