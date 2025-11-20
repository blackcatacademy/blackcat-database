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

namespace BlackCat\Database\Exceptions;

use BlackCat\Database\Support\SqlPreview;

/**
 * ViewVerificationException – indicates a violation of view contracts or directives.
 *
 * Usage:
 * - {@see self::drift()}           – general mismatch between definitions/directives.
 * - {@see self::columnsMismatch()} – differing columns/order/types.
 * - {@see self::sqlMismatch()}     – SQL text differs (stored as hashes to avoid leaking queries).
 *
 * Security notes:
 * - `got/expect` payloads are stored under `meta` with JSON truncated or hashed to avoid leaking large/sensitive data.
 * - Parameters are marked with {@see \SensitiveParameter} so tooling masks payloads.
 *
 * @phpstan-type Meta array<string,mixed>
 */
final class ViewVerificationException extends DdlException
{
    public const KIND_DRIFT   = 'drift';
    public const KIND_COLUMNS = 'columns_mismatch';
    public const KIND_SQL     = 'sql_mismatch';

    /**
     * Reports a generic mismatch between expected and actual view directives/schema.
     *
     * @param non-empty-string $view
     * @param array<string,mixed> $got
     * @param array<string,mixed> $expect
     * @param Meta $meta
     */
    public static function drift(
        string $view,
        #[\SensitiveParameter] array $got,
        #[\SensitiveParameter] array $expect,
        array $meta = [],
        ?\Throwable $previous = null
    ): self {
        $msg = "View directives mismatch for '{$view}' (see meta.got/meta.expect)";
        $m = self::enrichMeta($meta, self::KIND_DRIFT, [
            'got'    => self::compactJson($got),
            'expect' => self::compactJson($expect),
        ]);

        // DdlException(message, sqlState, dialect, objectName, statement, meta, previous)
        return new self($msg, null, null, $view, null, $m, $previous);
    }

    /**
     * Reports column mismatches (names/order/types).
     *
     * @param non-empty-string $view
     * @param list<array<string,mixed>|string> $gotColumns
     * @param list<array<string,mixed>|string> $expectColumns
     * @param Meta $meta
     */
    public static function columnsMismatch(
        string $view,
        #[\SensitiveParameter] array $gotColumns,
        #[\SensitiveParameter] array $expectColumns,
        array $meta = [],
        ?\Throwable $previous = null
    ): self {
        $msg = "View columns mismatch for '{$view}' (see meta.gotColumns/meta.expectColumns)";
        $m = self::enrichMeta($meta, self::KIND_COLUMNS, [
            'gotColumns'    => self::compactJson($gotColumns),
            'expectColumns' => self::compactJson($expectColumns),
        ]);

        return new self($msg, null, null, $view, null, $m, $previous);
    }

    /**
     * Reports SQL definition mismatches (contents are hashed so full queries are not logged).
     *
     * @param non-empty-string $view
     */
    public static function sqlMismatch(
        string $view,
        #[\SensitiveParameter] string $gotSql,
        #[\SensitiveParameter] string $expectSql,
        array $meta = [],
        ?\Throwable $previous = null
    ): self {
        $msg = "View SQL mismatch for '{$view}' (see meta.sql.gotHash/meta.sql.expectHash)";
        $m = self::enrichMeta($meta, self::KIND_SQL, [
            'sql' => [
                'gotHash'    => self::hashText($gotSql),
                'expectHash' => self::hashText($expectSql),
                // Provide a trimmed preview to aid debugging while keeping it short
                'gotPreview'    => SqlPreview::preview($gotSql),
                'expectPreview' => SqlPreview::preview($expectSql),
            ],
        ]);

        return new self($msg, null, null, $view, null, $m, $previous);
    }

    // ---------------- Internal helpers ----------------

    /** Adds the error kind into meta and merges in extra context. @param Meta $meta @return Meta */
    private static function enrichMeta(array $meta, string $kind, array $extra): array
    {
        return \array_merge(['kind' => $kind], $meta, $extra);
    }

    /**
     * Safe JSON helper – falls back to hash + preview when the payload is too large.
     *
     * @return array{json?:string,hash?:string,bytes:int,preview?:string}
     */
    private static function compactJson(mixed $value, int $maxBytes = 4096): array
    {
        $json = \json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($json === false) {
            return ['hash' => self::hashText('<<json_error>>'), 'bytes' => 0];
        }
        $bytes = \strlen($json);
        if ($bytes <= $maxBytes) {
            return ['json' => $json, 'bytes' => $bytes];
        }
        return [
            'hash'    => self::hashText($json),
            'bytes'   => $bytes,
            'preview' => SqlPreview::preview($json),
        ];
    }

    /** Convenience SHA-256 helper. */
    private static function hashText(string $s): string
    {
        return \hash('sha256', $s);
    }
}
