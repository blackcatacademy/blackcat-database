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

use BlackCat\Database\Support\Observability;

/**
 * OperationResult – immutable container for application/API operation outcomes.
 *
 * Goals and features:
 * - Simple factory methods (ok/fail + pre-configured notFound/validation/... helpers).
 * - Pure “with*” transformations returning new instances (no state mutation).
 * - Safe handling of error messages (single-line, truncated, no sensitive data).
 * - Stable JSON serialization with value normalization (DateTime → RFC3339, Traversable → array).
 * - Practical unwrapping helpers (unwrap*) and guard (requireOk).
 */
final class OperationResult implements \JsonSerializable
{
    /** @var array<string,int> */
    private const DEFAULT_HTTP_FOR_CODE = [
        'not_found'         => 404,
        'validation'        => 422,
        'bad_request'       => 400,
        'unauthorized'      => 401,
        'forbidden'         => 403,
        'conflict'          => 409,
        'gone'              => 410,
        'too_many_requests' => 429,
        'internal'          => 500,
    ];

    /**
     * @param array<string,mixed> $meta
     */
    public function __construct(
        public bool $ok,
        public mixed $data = null,
        public ?string $message = null,
        public ?string $correlationId = null,
        public array $meta = [],
        public ?string $code = null,     // e.g. 'not_found', 'validation'
        public ?int $httpStatus = null   // Optional HTTP mapping
    ) {}

    /* ---------- Static factories ---------- */

    /**
     * Successful result factory.
     * @param array<string,mixed> $meta
     */
    public static function ok(mixed $data = null, ?string $corr = null, array $meta = []): self
    {
        return new self(true, $data, null, $corr, $meta, null, null);
    }

    /**
     * Failure factory (without throwing). Code and HTTP status are normalized.
     * @param array<string,mixed> $meta
     */
    public static function fail(string $message, ?string $corr = null, array $meta = [], ?string $code = null, ?int $http = null): self
    {
        $normCode = self::cleanCode($code);
        $httpResolved = $http ?? ($normCode !== null ? (self::DEFAULT_HTTP_FOR_CODE[$normCode] ?? null) : null);
        return new self(false, null, self::cleanMsg($message, 300), $corr, $meta, $normCode, $httpResolved);
    }

    /** Safe wrapper around throwables (prevents leaking sensitive info). */
    public static function fromThrowable(\Throwable $e, ?string $corr = null, array $meta = [], ?string $code = null, ?int $http = 500): self
    {
        $msg = self::cleanMsg((string)$e->getMessage(), 300);
        $m   = $meta + ['class' => (new \ReflectionClass($e))->getName()];
        $normCode = self::cleanCode($code) ?? 'internal';
        $httpResolved = $http ?? (self::DEFAULT_HTTP_FOR_CODE[$normCode] ?? 500);
        return new self(false, null, $msg, $corr, $m, $normCode, $httpResolved);
    }

    /** Returns ok when $value !== null, otherwise fail('not_found', 404). */
    public static function fromNullable(mixed $value, string $notFoundMessage = 'Not found', ?string $corr = null, array $meta = []): self
    {
        return $value !== null
            ? self::ok($value, $corr, $meta)
            : self::fail($notFoundMessage, $corr, $meta, 'not_found', 404);
    }

    // Predefined factories for convenience (idiomatic API)
    public static function notFound(string $message = 'Not found', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'not_found', 404); }

    public static function validation(string $message = 'Validation error', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'validation', 422); }

    public static function badRequest(string $message = 'Bad request', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'bad_request', 400); }

    public static function unauthorized(string $message = 'Unauthorized', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'unauthorized', 401); }

    public static function forbidden(string $message = 'Forbidden', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'forbidden', 403); }

    public static function conflict(string $message = 'Conflict', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'conflict', 409); }

    public static function gone(string $message = 'Gone', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'gone', 410); }

    public static function tooManyRequests(string $message = 'Too many requests', ?string $corr = null, array $meta = []): self
    { return self::fail($message, $corr, $meta, 'too_many_requests', 429); }

    /* ---------- Transformations & combinators ---------- */

    /** Maps the contained data while keeping everything else. */
    public function map(callable $fn): self
    {
        return $this->ok
            ? new self(true, $fn($this->data), null, $this->correlationId, $this->meta, $this->code, $this->httpStatus)
            : $this;
    }

    /**
     * FlatMap: when ok, expects OperationResult from the callback (otherwise wraps the value in ok()).
     */
    public function andThen(callable $fn): self
    {
        if (!$this->ok) return $this;
        $next = $fn($this->data);
        return $next instanceof self ? $next : self::ok($next, $this->correlationId, $this->meta);
    }

    /** Transforms the error (message/code/http/meta) while keeping data null. */
    public function mapError(callable $fn): self
    {
        if ($this->ok) return $this;
        $new = $fn($this);
        return $new instanceof self
            ? $new
            : new self(false, null, $this->message, $this->correlationId, $this->meta, $this->code, $this->httpStatus);
    }

    /** Fallback: when failing, call $fallback and return its result. */
    public function orElse(callable $fallback): self
    {
        return $this->ok ? $this : $fallback($this);
    }

    /** Runs a side effect (logging, etc.) and returns itself. */
    public function tap(callable $fn): self
    {
        $fn($this);
        return $this;
    }

    /** Adds/merges metadata (left-biased: $extra + $this->meta). */
    public function withMeta(array $extra): self
    {
        return new self($this->ok, $this->data, $this->message, $this->correlationId, $extra + $this->meta, $this->code, $this->httpStatus);
    }

    public function withCode(?string $code): self
    {
        $normCode = self::cleanCode($code);
        $http = $this->httpStatus ?? ($normCode !== null ? (self::DEFAULT_HTTP_FOR_CODE[$normCode] ?? null) : null);
        return new self($this->ok, $this->data, $this->message, $this->correlationId, $this->meta, $normCode, $http);
    }

    public function withHttp(?int $http): self
    {
        return new self($this->ok, $this->data, $this->message, $this->correlationId, $this->meta, $this->code, $http);
    }

    public function withMessage(?string $message): self
    {
        return new self($this->ok, $this->data, self::cleanMsg((string)$message), $this->correlationId, $this->meta, $this->code, $this->httpStatus);
    }

    public function withData(mixed $data): self
    {
        return new self($this->ok, $data, $this->message, $this->correlationId, $this->meta, $this->code, $this->httpStatus);
    }

    public function withCorr(?string $corr): self
    {
        return new self($this->ok, $this->data, $this->message, $corr, $this->meta, $this->code, $this->httpStatus);
    }

    /** Throws if the result is not ok (useful in application layers). */
    public function requireOk(?\Throwable $throwable = null): self
    {
        if ($this->ok) return $this;
        throw $throwable ?? new \RuntimeException($this->message ?? 'Operation failed');
    }

    /** Convenience unwrapping helper. */
    public function unwrapOr(mixed $default): mixed { return $this->ok ? $this->data : $default; }

    public function unwrapOrElse(callable $fn): mixed { return $this->ok ? $this->data : $fn($this); }

    public function isOk(): bool { return $this->ok; }

    public function isFail(): bool { return !$this->ok; }

    /* ---------- JSON output ---------- */

    /**
     * @return array{
     *   ok: bool,
     *   data: mixed,
     *   err: null|array{message:?string,code:?string,http:?int},
     *   corr: ?string,
     *   meta: array<string,mixed>
     * }
     */
    public function jsonSerialize(): array
    {
        return [
            'ok'   => $this->ok,
            'data' => self::normalizeForJson($this->data),
            'err'  => $this->ok ? null : [
                'message' => $this->message,
                'code'    => $this->code,
                'http'    => $this->httpStatus,
            ],
            'corr' => $this->correlationId,
            'meta' => $this->meta,
        ];
    }

    public function toArray(): array
    {
        return $this->jsonSerialize();
    }

    /** Optional helper when a JSON string is required (without leaking exceptions). */
    public function toJson(int $flags = 0): string
    {
        try {
            return \json_encode($this, \JSON_UNESCAPED_UNICODE | \JSON_UNESCAPED_SLASHES | $flags | \JSON_THROW_ON_ERROR);
        } catch (\Throwable) {
            $s = \json_encode($this, \JSON_UNESCAPED_UNICODE | \JSON_UNESCAPED_SLASHES | $flags);
            return $s === false ? '{"ok":false,"err":{"message":"json_encode_failed"},"data":null}' : $s;
        }
    }

    /* ---------- Internal helpers ---------- */

    private static function cleanMsg(string $s, int $max = 300): string
    {
        // Enforce single-line + strip control characters
        $s = \str_replace(["\r", "\n", "\t"], ' ', $s);
        $s = \preg_replace('/[\x00-\x1F\x7F]+/u', '', $s) ?? $s;
        $s = \preg_replace('/\s+/u', ' ', $s) ?? $s;
        return Observability::clip(\trim($s), $max);
    }

    private static function cleanCode(?string $code): ?string
    {
        if ($code === null) return null;
        $c = \strtolower(\preg_replace('~[^a-z0-9_.-]+~', '-', $code) ?? '');
        return $c !== '' ? $c : null;
    }

    /** Recursive normalization for JSON (dates → RFC3339, objects → serializable form). */
    private static function normalizeForJson(mixed $v): mixed
    {
        if ($v instanceof \DateTimeInterface) {
            return $v->format(\DATE_ATOM);
        }
        if ($v instanceof \JsonSerializable) {
            return $v->jsonSerialize();
        }
        if ($v instanceof \Traversable) {
            $tmp = [];
            foreach ($v as $k => $vv) { $tmp[$k] = self::normalizeForJson($vv); }
            return $tmp;
        }
        if (\is_array($v)) {
            $out = [];
            foreach ($v as $k => $vv) { $out[$k] = self::normalizeForJson($vv); }
            return $out;
        }
        if (\is_object($v)) {
            return \method_exists($v, '__toString') ? (string)$v : 'object(' . (new \ReflectionClass($v))->getName() . ')';
        }
        if (\is_resource($v)) {
            return 'resource';
        }
        return $v;
    }
}
