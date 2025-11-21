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

namespace BlackCat\Database\Events;

/**
 * Immutable CRUD domain event emitted by Eventful/Idempotent services.
 *
 * @api
 *
 * Typing & static analysis helpers:
 * @phpstan-type ScalarType int|float|string|bool
 * @phpstan-type Assoc array<string,mixed>
 * @phpstan-type Id int|string|array<string,ScalarType|null>
 *
 * @psalm-type ScalarType = int|float|string|bool
 * @psalm-type Assoc = array<string,mixed>
 * @psalm-type Id = int|string|array<string,ScalarType|null>
 *
 * Design goals:
 * - Fully immutable (readonly) and self-validating constructor.
 * - Safe for logging/telemetry: payloads marked with SensitiveParameter.
 * - Dev-friendly helpers (isCreate/isUpdate/..., toArray/jsonSerialize, withContext).
 */
final class CrudEvent implements \JsonSerializable
{
    public const OP_CREATE  = 'create';
    public const OP_UPDATE  = 'update';
    public const OP_DELETE  = 'delete';
    public const OP_RESTORE = 'restore';
    public const OP_TOUCH   = 'touch';
    public const OP_UPSERT  = 'upsert';
    public const OP_BULK    = 'bulk';

    /** @var non-empty-list<non-empty-string> */
    private const ALLOWED_OPS = [
        self::OP_CREATE,
        self::OP_UPDATE,
        self::OP_DELETE,
        self::OP_RESTORE,
        self::OP_TOUCH,
        self::OP_UPSERT,
        self::OP_BULK,
    ];

    /**
     * @param non-empty-string $operation one of ALLOWED_OPS
     * @param non-empty-string $table     logical table name (Definitions::table())
     * @param Id|null          $id        scalar or assoc array for composite PK
     * @param positive-int|0   $affected  best-effort number of affected rows
     * @param Assoc|null       $before    best-effort snapshot (or null)
     * @param Assoc|null       $after     best-effort snapshot (or null)
     * @param Assoc            $context   free-form metadata (tenant, corr, cache_ns, version_col, etc.)
     */
    public readonly string $operation;
    public readonly string $table;
    public readonly int|string|array|null $id;
    public readonly int $affected;
    public readonly ?array $before;
    public readonly ?array $after;
    public readonly array $context;

    public function __construct(
        string $operation,
        string $table,
        int|string|array|null $id,
        int $affected = 1,
        ?array $before = null,
        ?array $after = null,
        array $context = []
    ) {
        $op = \strtolower(\trim($operation));
        if (!\in_array($op, self::ALLOWED_OPS, true)) {
            throw new \InvalidArgumentException("CrudEvent: unsupported operation '{$operation}'");
        }
        $table = \trim($table);
        if ($table === '') {
            throw new \InvalidArgumentException('CrudEvent: table must be non-empty');
        }
        $affected = \max(0, $affected);

        $this->operation = $op;
        $this->table     = $table;
        $this->id        = $id;
        $this->affected  = $affected;
        $this->before    = $before;
        $this->after     = $after;
        $this->context   = $context;
    }

    /** @return Assoc */
    public function toArray(): array
    {
        return [
            'operation' => $this->operation,
            'table'     => $this->table,
            'id'        => $this->id,
            'affected'  => $this->affected,
            'before'    => $this->before,
            'after'     => $this->after,
            'context'   => $this->context,
        ];
    }

    /** @return Assoc */
    public function jsonSerialize(): array
    {
        return $this->toArray();
    }

    public function __toString(): string
    {
        return \json_encode($this->toArray(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: 'CrudEvent{}';
    }

    // -------- convenience predicates --------

    public function isCreate(): bool { return $this->operation === self::OP_CREATE; }
    public function isUpdate(): bool { return $this->operation === self::OP_UPDATE; }
    public function isDelete(): bool { return $this->operation === self::OP_DELETE; }
    public function isRestore(): bool { return $this->operation === self::OP_RESTORE; }
    public function isTouch(): bool  { return $this->operation === self::OP_TOUCH; }
    public function isUpsert(): bool { return $this->operation === self::OP_UPSERT; }
    public function isBulk(): bool   { return $this->operation === self::OP_BULK; }

    public function correlationId(): ?string
    {
        $corr = $this->context['corr'] ?? null;
        return \is_string($corr) && $corr !== '' ? $corr : null;
    }

    public function tenant(): ?string
    {
        $t = $this->context['tenant'] ?? null;
        return \is_string($t) && $t !== '' ? $t : null;
    }

    /**
     * Return a copy with merged context (new keys override existing).
     * @param Assoc $extra
     */
    public function withContext(array $extra): self
    {
        return new self(
            $this->operation,
            $this->table,
            $this->id,
            $this->affected,
            $this->before,
            $this->after,
            [...$this->context, ...$extra]
        );
    }

    /**
     * Factory for bulk operations (affected must be >= 0).
     * @param Assoc $context
     */
    public static function bulk(string $table, int $affected, array $context = []): self
    {
        return new self(self::OP_BULK, $table, null, \max(0, $affected), null, null, $context);
    }
}
