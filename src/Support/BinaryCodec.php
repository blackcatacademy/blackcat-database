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
 * BinaryCodec – robust conversion of "some binary input" into a real binary string.
 *
 * Goal:
 * - Accept multiple representations of binary data (PG bytea \xDEAD…, MySQL 0xDEAD…,
 *   SQL literal x'DEAD', data:*;base64, plain base64, stream resources) and return **raw** binary.
 * - API remains BC: both methods return **binary string or null** (never throw),
 *   empty string => null.
 *
 * Notes:
 * - `fromBinary()` is just an alias to the decoder like `toBinary()` (BC with existing code).
 * - If the input is not recognized (e.g., plain text), return the original string (it might already be binary);
 *   only empty string/null => null.
 */
final class BinaryCodec
{
    /** Accept various sources and return a raw binary string or null. */
    public static function toBinary(mixed $v): ?string
    {
        return self::decodeToBinary($v);
    }

    /** Alias to the decoder (for BC). */
    public static function fromBinary(mixed $v): ?string
    {
        return self::decodeToBinary($v);
    }

    // ---------------- internal decoder ----------------

    private static function decodeToBinary(mixed $v): ?string
    {
        // null / '' -> null
        if ($v === null || $v === '') {
            return null;
        }

        // Stream resource
        if (\is_resource($v)) {
            try {
                $data = \stream_get_contents($v);
                return ($data === false || $data === '') ? null : $data;
            } catch (\Throwable) {
                return null;
            }
        }

        // PSR-7 stream (avoid a hard dependency – rely on a reasonable interface)
        if (\is_object($v) && \method_exists($v, '__toString')) {
            try {
                $s = (string)$v;
                return $s === '' ? null : self::decodeString($s);
            } catch (\Throwable) {
                return null;
            }
        }

        // String
        if (\is_string($v)) {
            return self::decodeString($v);
        }

        // Otherwise unknown
        return null;
    }

    /**
     * @param string $s
     */
    private static function decodeString(string $s): ?string
    {
        $s = \trim($s);
        if ($s === '') {
            return null;
        }

        // 1) PostgreSQL bytea (hex format): "\xDEADBEEF" or "\\xDEADBEEF" (escaped from JSON/PDO)
        if (\str_starts_with($s, '\\\\x')) {
            $hex = \substr($s, 3); // skip "\\x"
            $hex = \preg_replace('~\s+~', '', $hex) ?? $hex; // remove potential spaces
            return self::isHex($hex) ? (\hex2bin($hex) ?: null) : $s;
        }
        if (\str_starts_with($s, '\\x')) {
            $hex = \ltrim(\ltrim($s, '\\'), 'x');
            $hex = \preg_replace('~\s+~', '', $hex) ?? $hex; // remove potential spaces
            return self::isHex($hex) ? (\hex2bin($hex) ?: null) : $s;
        }

        // 2) MySQL "0xDEADBEEF"
        if (\str_starts_with($s, '0x') || \str_starts_with($s, '0X')) {
            $hex = \substr($s, 2);
            $hex = \preg_replace('~\s+~', '', $hex) ?? $hex;
            return self::isHex($hex) ? (\hex2bin($hex) ?: null) : $s;
        }

        // 3) SQL literal "x'DEAD BEEF'" (optional whitespace allowed)
        if (\preg_match("~^x'([0-9A-Fa-f\\s]+)'$~", $s, $m) === 1) {
            $hex = \preg_replace('~\s+~', '', $m[1]) ?? $m[1];
            return self::isHex($hex) ? (\hex2bin($hex) ?: null) : $s;
        }

        // 4) data:*;base64,...
        if (\str_starts_with($s, 'data:') && \str_contains($s, ';base64,')) {
            $b64 = \substr($s, (int)\strpos($s, ';base64,') + 8);
            $bin = \base64_decode($b64, true);
            return ($bin === false || $bin === '') ? null : $bin;
        }

        // 5) Plain base64 (careful – only if it looks valid)
        if (self::looksLikeBase64($s)) {
            $bin = \base64_decode($s, true);
            if ($bin !== false && $bin !== '') {
                // Quick validation: re-encoding (trimming '=' padding) should match
                $r = \rtrim(\base64_encode($bin), '=');
                $q = \rtrim($s, '=');
                if ($r === $q) {
                    return $bin;
                }
            }
            // If decoding fails, do not treat it as base64
        }

        // 6) Old PG bytea "escaped" format (\\123 octal + \\ as backslash)
        // recognize if it contains "\xxx" sequences or doubled backslashes.
        if (\str_contains($s, '\\')) {
            $maybe = self::tryUnescapePgByteaEscaped($s);
            if ($maybe !== null) {
                return $maybe;
            }
        }

        // 7) Fallback – treat it as an already binary string
        return $s;
    }

    // ---------------- utility ----------------

    private static function isHex(string $s): bool
    {
        // Even length and digits 0-9A-F only
        $len = \strlen($s);
        return ($len > 0 && ($len % 2) === 0 && \ctype_xdigit($s));
    }

    private static function looksLikeBase64(string $s): bool
    {
        // Base64 charset + optional padding, length multiple of 4
        $len = \strlen($s);
        if ($len < 8 || ($len % 4) !== 0) {
            return false;
        }
        if (!\preg_match('~^[A-Za-z0-9+/]+={0,2}$~', $s)) {
            return false;
        }
        return true;
    }

    /**
     * Attempt to decode the old PG bytea "escape" format:
     *  - sequence \\xyz (octal) -> corresponding byte
     *  - \\ -> \ (escaped backslash)
     */
    private static function tryUnescapePgByteaEscaped(string $s): ?string
    {
        // If the string lacks "\\" or "\123" sequences it is likely not this format.
        if (!\str_contains($s, '\\')) {
            return null;
        }

        // Quick scan: if pattern \\\\ or \\[0-7]{3} is absent, decoding makes no sense.
        if (\preg_match('~\\\\\\\\|\\\\[0-7]{3}~', $s) !== 1) {
            return null;
        }

        $out = '';
        $len = \strlen($s);
        for ($i = 0; $i < $len; $i++) {
            $ch = $s[$i];
            if ($ch !== '\\') {
                $out .= $ch;
                continue;
            }
            // Saw a backslash – try \\\\ or \[0-7]{3}
            if ($i + 1 < $len && $s[$i + 1] === '\\') {
                $out .= '\\';
                $i += 1;
                continue;
            }
            if ($i + 3 < $len) {
                $oct = \substr($s, $i + 1, 3);
                if (\preg_match('~^[0-7]{3}$~', $oct) === 1) {
                    $out .= \chr((int)\octdec($oct));
                    $i += 3;
                    continue;
                }
            }
            // Unknown sequence – keep the backslash
            $out .= '\\';
        }

        return $out;
    }
}
