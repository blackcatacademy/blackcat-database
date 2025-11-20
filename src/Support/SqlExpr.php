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

use BlackCat\Core\Database;

/**
 * SqlExpr – safe immutable holder for raw SQL fragments + parameters.
 *
 * Notes:
 * - 'expr' is a fragment (expression), not the whole statement; trailing ';' is trimmed.
 * - Parameters are normalized to ':name'. Numeric keys -> ':p0', ':p1', ...
 * - Instance is immutable; all modifiers return a new instance.
 *
 * @psalm-type SqlParams = array<string, mixed>
 */
final class SqlExpr implements \Stringable, \JsonSerializable
{
    /** Raw SQL fragment (trusted) */
    public readonly string $expr;

    /** @var SqlParams Normalized parameters attached to the fragment */
    public readonly array $params;

    /**
     * @param array<string|int, mixed> $params
     */
    public function __construct(string $expr, array $params = [])
    {
        $e = self::trimTrailingSemicolons(trim($expr));
        self::assertNoMidStatementSemicolon($e);
        $this->expr   = $e;
        $this->params = self::normalizeParams($params);
    }

    /** Short factory. */
    public static function raw(string $expr, array $params = []): self
    {
        return new self($expr, $params);
    }

    /**
     * List of safely quoted identifiers – useful for SELECT/ORDER/GROUP BY clauses.
     * Example: SqlExpr::identList($db, ['id','created_at']) → `"id", "created_at"`
     *
     * @param array<int,string> $idents
     */
    public static function identList(Database $db, array $idents, string $sep = ', '): self
    {
        $q = [];
        foreach ($idents as $i) {
            $q[] = \BlackCat\Database\Support\SqlIdentifier::q($db, (string)$i);
        }
        return new self(implode($sep, $q));
    }

    /**
     * Build a function call.
     * Parameters are merged in argument order (without overwriting earlier keys).
     */
    public static function func(string $name, string|self ...$args): self
    {
        self::assertSafeFuncName($name);

        $parts  = [];
        $params = [];
        foreach ($args as $a) {
            if ($a instanceof self) {
                $parts[] = $a->expr;
                foreach ($a->params as $k => $v) {
                    // Preserve the first occurrence of each key
                    if (!array_key_exists($k, $params)) {
                        $params[$k] = $v;
                    }
                }
            } else {
                $parts[] = $a;
            }
        }
        return new self($name . '(' . implode(', ', $parts) . ')', $params);
    }

    /** Append another fragment separated by a space. */
    public function append(string|self $tail): self
    {
        return $this->merge($tail, ' ');
    }

    /** Append another fragment using a custom separator. */
    public function merge(string|self $tail, string $glue = ' '): self
    {
        if ($tail instanceof self) {
            $tExpr = $tail->expr;
            $tParams = $tail->params;
        } else {
            $tExpr = trim($tail);
            $tParams = [];
        }
        if ($tExpr === '') {
            return $this;
        }
        $expr = ($this->expr === '') ? $tExpr : ($this->expr . $glue . $tExpr);
        return new self($expr, $this->params + $tParams);
    }

    /** Wrap the fragment with a prefix/suffix (e.g., parentheses). */
    public function wrap(string $prefix = '(', string $suffix = ')'): self
    {
        if ($this->expr === '') return $this;
        return new self($prefix . $this->expr . $suffix, $this->params);
    }

    /**
     * Join multiple fragments with the given glue (skipping empty ones).
     * @param array<int,string|self> $parts
     */
    public static function join(array $parts, string $glue = ' '): self
    {
        $exprs  = [];
        $params = [];
        foreach ($parts as $p) {
            if ($p instanceof self) {
                if ($p->expr === '') continue;
                $exprs[] = $p->expr;
                foreach ($p->params as $k => $v) {
                    if (!array_key_exists($k, $params)) {
                        $params[$k] = $v;
                    }
                }
            } else {
                $pp = trim($p);
                if ($pp !== '') $exprs[] = $pp;
            }
        }
        return new self(implode($glue, $exprs), $params);
    }

    /** Add or replace a parameter (name normalized to ':name'). */
    public function withParam(string $name, mixed $value): self
    {
        $norm = self::normalizeParamKey($name);
        $p = $this->params;
        $p[$norm] = $value;
        return new self($this->expr, $p);
    }

    /** True if the expression is empty. */
    public function isEmpty(): bool
    {
        return $this->expr === '';
    }

    /** String cast – convenient for SQL builders. */
    public function __toString(): string
    {
        return $this->expr;
    }

    /** @return array{expr:string,params:array<string,mixed>} */
    public function jsonSerialize(): array
    {
        return ['expr' => $this->expr, 'params' => $this->params];
    }

    /** Limited debug dump. */
    public function __debugInfo(): array
    {
        return [
            'expr'   => $this->expr,
            'params' => array_map(static fn($v) => is_scalar($v) ? $v : gettype($v), $this->params),
        ];
    }

    /* ==================== Internal helpers ==================== */

    private static function trimTrailingSemicolons(string $s): string
    {
        // Remove only trailing semicolons and whitespace
        return rtrim($s, " \t\n\r\0\x0B;");
    }

    private static function assertNoMidStatementSemicolon(string $s): void
    {
        // Simple check – disallow ';' outside quotes
        $inSingle = false; $inDouble = false; $len = strlen($s);
        for ($i = 0; $i < $len; $i++) {
            $ch = $s[$i];
            $prev = $i > 0 ? $s[$i - 1] : null;

            if ($ch === "'" && !$inDouble && $prev !== '\\') { $inSingle = !$inSingle; continue; }
            if ($ch === '"' && !$inSingle && $prev !== '\\') { $inDouble = !$inDouble; continue; }

            if (!$inSingle && !$inDouble && $ch === ';') {
                throw new \InvalidArgumentException('SqlExpr expects a fragment (no mid-statement semicolons).');
            }
        }
    }

    /**
     * @param array<string|int,mixed> $p
     * @return SqlParams
     */
    private static function normalizeParams(array $p): array
    {
        $out = [];
        $auto = 0;
        foreach ($p as $k => $v) {
            if (is_int($k)) {
                $key = ':p' . $auto++;
            } else {
                $key = self::normalizeParamKey($k);
            }
            $out[$key] = $v;
        }
        return $out;
    }

    private static function normalizeParamKey(string $k): string
    {
        $kk = ltrim($k, ':');
        // Only allow a-z0-9_ for consistent placeholders
        $kk = preg_replace('~[^a-zA-Z0-9_]+~', '_', $kk) ?? $kk;
        return ':' . $kk;
    }

    private static function assertSafeFuncName(string $name): void
    {
        if (!preg_match('~^[A-Za-z_][A-Za-z0-9_\.]*$~', $name)) {
            throw new \InvalidArgumentException('Unsafe SQL function name.');
        }
    }
}
