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
 * JsonCodec – safe JSON serialization/deserialization with zero outward exceptions.
 *
 * Design:
 * - `decode(mixed $v): ?array`
 *      - Returns an array (assoc/list) or `null`. `stdClass` is converted to array.
 *      - Empty string / "null" (case-insensitive) / null → `null`.
 *      - If the JSON represents a **scalar** (number/bool/string), return `null` (BC with existing API).
 *      - For resources, try reading the stream and decode.
 *      - For `JsonSerializable` objects, serialize first and decode that.
 *      - For other non-string values keep the original behavior (cast to array).
 *
 * - `encode(mixed $v): ?string`
 *      - Returns JSON string or `null` (for `null` input).
 *      - Uses flags for nicer and more robust output (UNICODE, SLASHES, ZERO_FRACTION, INVALID_UTF8_SUBSTITUTE).
 *      - Fall back without `JSON_THROW_ON_ERROR`, so it never propagates an exception outward.
 */
final class JsonCodec
{
    private const DECODE_DEPTH = 512;

    /** Preferred flags for encode (no outward exceptions). */
    private const JSON_FLAGS = \JSON_UNESCAPED_UNICODE
                             | \JSON_UNESCAPED_SLASHES
                             | \JSON_PRESERVE_ZERO_FRACTION
                             | \JSON_INVALID_UTF8_SUBSTITUTE;

    /**
     * @return array<mixed>|null
     */
    public static function decode(mixed $v): ?array
    {
        if ($v === null) {
            return null;
        }

        // Direct array → return it
        if (\is_array($v)) {
            return $v;
        }

        // stdClass → array
        if ($v instanceof \stdClass) {
            /** @var array<mixed> */
            return (array)$v;
        }

        // JsonSerializable object → serialize and decode
        if ($v instanceof \JsonSerializable) {
            try {
                $json = \json_encode($v, self::JSON_FLAGS | \JSON_THROW_ON_ERROR);
            } catch (\Throwable) {
                $json = \json_encode($v, self::JSON_FLAGS) ?: null;
            }
            return $json !== null ? self::decode($json) : null;
        }

        // Resource stream → read and try to decode
        if (\is_resource($v)) {
            try {
                $s = \stream_get_contents($v);
                if ($s === false) {
                    return null;
                }
                return self::decode($s);
            } catch (\Throwable) {
                return null;
            }
        }

        // Objects with __toString – convert and decode
        if (\is_object($v) && \method_exists($v, '__toString')) {
            try {
                return self::decode((string)$v);
            } catch (\Throwable) {
                return null;
            }
        }

        // String path
        if (!\is_string($v)) {
            // BC: unknown non-string type -> cast to array (original behavior)
            /** @var array<mixed> */
            return (array)$v;
        }

        $t = \trim($v);
        if ($t === '' || \strtolower($t) === 'null') {
            return null;
        }

        // Quick check "looks like JSON collection" – optimization only
        // (still run json_decode below with throw and fallback).
        $first = $t[0] ?? '';
        $looksJson = $first === '{' || $first === '[';

        // Primary attempt – strict mode (exception -> fallback)
        try {
            $x = \json_decode($t, true, self::DECODE_DEPTH, \JSON_THROW_ON_ERROR);
            return \is_array($x) ? $x : null; // scalary -> null (API kontrakt)
        } catch (\JsonException) {
            // Fallback tolerant to minor issues (invalid UTF-8, etc.)
            $x = \json_decode($t, true);
            return \is_array($x) ? $x : ($looksJson ? null : null);
        }
    }

    /**
     * @return non-empty-string|null
     */
    public static function encode(mixed $v): ?string
    {
        if ($v === null) {
            return null;
        }

        // Primary attempt with throw (better errors and exact output)
        try {
            /** @var string $json */
            $json = \json_encode($v, self::JSON_FLAGS | \JSON_THROW_ON_ERROR);
            return $json;
        } catch (\Throwable) {
            // Fallback without exceptions; if that fails, return `null`
            $json = \json_encode($v, self::JSON_FLAGS);
            return $json === false ? null : $json;
        }
    }
}
