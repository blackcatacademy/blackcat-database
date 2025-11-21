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

use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;

/**
 * Casts – safe and predictable conversions of common types.
 *
 * Principles:
 * - `null` and empty/whitespace strings -> `null` (never throw).
 * - Text values are processed with **trim + casefold**.
 * - Prevent PHP's "magic" conversions like `(int)"123abc" === 123` -> such inputs return `null`.
 * - Numeric strings: accept only valid shapes (for `float` also accept `1,23` -> 1.23 when no dot exists).
 * - Epoch seconds/ms supported in `toDate()` for numeric inputs.
 *
 * @phpstan-type MaybeBool  bool|null
 * @phpstan-type MaybeInt   int|null
 * @phpstan-type MaybeFloat float|null
 */
final class Casts
{
    /** @var array<string|int,bool> */
    private const TRUE_LUT = [
        '1'=>true, 'true'=>true, 't'=>true, 'yes'=>true, 'y'=>true, 'on'=>true, 'ok'=>true,
    ];

    /** @var array<string|int,bool> */
    private const FALSE_LUT = [
        '0'=>true, 'false'=>true, 'f'=>true, 'no'=>true, 'n'=>true, 'off'=>true,
    ];

    /**
     * Safe conversion to bool.
     *
     * Accepted "true": 1, true, "1", "true", "t", "yes", "y", "on", "ok"
     * Accepted "false": 0, false, "0", "false", "f", "no", "n", "off"
     * Otherwise: `null` (except other scalars -> fall back to bool cast to keep BC for some inputs)
     *
     * @return MaybeBool
     */
    public static function toBool(mixed $v): ?bool
    {
        if ($v === null) {
            return null;
        }
        if (\is_bool($v)) {
            return $v;
        }
        if (\is_int($v)) {
            return $v !== 0;
        }
        if (\is_float($v)) {
            return $v != 0.0; // intentionally loose comparison for -0.0
        }
        if (\is_string($v)) {
            $s = \strtolower(\trim($v));
            if ($s === '') {
                return null;
            }
            if (isset(self::TRUE_LUT[$s])) {
                return true;
            }
            if (isset(self::FALSE_LUT[$s])) {
                return false;
            }
            // String consisting only of spaces → null (already handled above)
            return null;
        }

        // Last resort – preserve the original intent (e.g., non-empty array -> true)
        return (bool)$v;
    }

    /**
     * Safe conversion to int.
     * - Accepts int, float (truncates the fractional part), bool (0/1).
     * - For strings accepts only numeric forms with optional sign (e.g., "-42").
     * - "123abc" etc. → `null` (unlike native cast).
     *
     * @return MaybeInt
     */
    public static function toInt(mixed $v): ?int
    {
        if ($v === null) {
            return null;
        }
        if (\is_int($v)) {
            return $v;
        }
        if (\is_bool($v)) {
            return $v ? 1 : 0;
        }
        if (\is_float($v)) {
            return (int)$v;
        }
        if (\is_string($v)) {
            $s = \trim($v);
            if ($s === '') {
                return null;
            }
            // Pure integer (±) – no spaces/separators
            if (\preg_match('~^[+-]?\d+$~', $s) === 1) {
                // Range check via filter_var (protect against overflow on 32-bit systems)
                $i = \filter_var($s, \FILTER_VALIDATE_INT);
                return $i === false ? (int)$s : $i;
            }
            // Format with dot/comma → parse as float and then int
            if (\preg_match('~^[+-]?\d+[.,]\d+$~', $s) === 1) {
                $s = \str_contains($s, ',') && !\str_contains($s, '.') ? \str_replace(',', '.', $s) : $s;
                $f = \filter_var($s, \FILTER_VALIDATE_FLOAT);
                return $f === false ? null : (int)$f;
            }
            return null;
        }
        return null;
    }

    /**
     * Safe conversion to float.
     * - Accepts float, int, bool.
     * - For strings accepts standard decimal notation (dot or comma – not both).
     * - "123abc" etc. → `null`.
     *
     * @return MaybeFloat
     */
    public static function toFloat(mixed $v): ?float
    {
        if ($v === null) {
            return null;
        }
        if (\is_float($v)) {
            return $v;
        }
        if (\is_int($v)) {
            return (float)$v;
        }
        if (\is_bool($v)) {
            return $v ? 1.0 : 0.0;
        }
        if (\is_string($v)) {
            $s = \trim($v);
            if ($s === '') {
                return null;
            }
            // Digits with optional dot/comma and exponent
            // Allow a comma version (convert to dot if one is not already present)
            if (\str_contains($s, ',') && !\str_contains($s, '.')) {
                $s = \str_replace(',', '.', $s);
            }
            if (\preg_match('~^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$~', $s) !== 1) {
                return null;
            }
            $f = \filter_var($s, \FILTER_VALIDATE_FLOAT);
            return $f === false ? null : (float)$f;
        }
        return null;
    }

    /**
     * Safe conversion to DateTimeImmutable in the provided timezone.
     * - `DateTimeImmutable`/`DateTimeInterface` → clone + set TZ.
     * - integer/string number → epoch seconds **or** milliseconds (>= 10^12) → convert to seconds.
     * - string → passed to PHP's parser (respects embedded timezone; otherwise uses `$tz`).
     *
     * @return DateTimeImmutable|null
     */
    public static function toDate(mixed $v, DateTimeZone $tz): ?DateTimeImmutable
    {
        if ($v === null) {
            return null;
        }

        // Already a DateTime
        if ($v instanceof DateTimeImmutable) {
            return $v->setTimezone($tz);
        }
        if ($v instanceof DateTimeInterface) {
            // Preserve microseconds and time component
            return DateTimeImmutable::createFromInterface($v)->setTimezone($tz);
        }

        // Numeric epoch (seconds or milliseconds)
        if (\is_int($v) || (\is_string($v) && \ctype_digit(\trim($v)))) {
            $num = (int)\trim((string)$v);
            // Heuristic: 13+ digits = milliseconds
            if (\strlen((string)\abs($num)) >= 13) {
                $num = (int)\floor($num / 1000);
            }
            // '@' always means epoch seconds in UTC; then convert to $tz
            return (new DateTimeImmutable('@' . (string)$num))->setTimezone($tz);
        }

        // Explicit "now"
        if (\is_string($v) && \trim(\strtolower($v)) === 'now') {
            return new DateTimeImmutable('now', $tz);
        }

        // Generic string – let PHP parse it
        if (\is_string($v)) {
            $s = \trim($v);
            if ($s === '') {
                return null;
            }
            try {
                // If the string embeds a timezone it is used; otherwise fall back to $tz.
                return new DateTimeImmutable($s, $tz);
            } catch (\Throwable) {
                return null;
            }
        }

        return null;
    }
}
