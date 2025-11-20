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

namespace BlackCat\Database\Outbox;

use BlackCat\Database\Events\CrudEvent;

/**
 * OutboxRecord
 *
 * Lightweight immutable event carrier for the SQL outbox.
 * - `eventType`: logical event type (e.g. `crud.create`, `order.paid`).
 * - `payloadJson`: **valid** JSON string (never modified inside this class).
 * - `aggregateTable` + `aggregateId`: optional target/identity (routing/sharding).
 * - `routingKey`, `tenant`, `traceId`: optional metadata for transport/observability.
 * - TODO(crypto-integrations): add manifest-derived crypto metadata (context IDs, adapter
 *   fingerprints) so outbox publishers/consumers can prove payloads already passed through
 *   the DatabaseIngressAdapter before leaving the repository.
 *
 * Safety & DX:
 * - Constructor **does not normalize** (to preserve BC) but performs basic validation:
 *   non-empty `eventType` and valid JSON in `payloadJson`.
 * - Factory helpers for convenient/safe creation:
 *   - {@see self::fromPayloadArray()} – accepts an array and JSON-encodes it safely.
 *   - {@see self::fromCrudEvent()} – wraps a domain `CrudEvent`.
 * - `with*()` methods clone the record with updated metadata (readonly preserved).
 *
 * Note: intentionally keeps **public readonly** properties for BC with existing code.
 */
final class OutboxRecord implements \JsonSerializable
{
    /** Soft safety limits (not enforced at runtime; used inside factories). */
    private const EVENT_TYPE_MAX = 128;
    private const ROUTING_MAX    = 255;
    private const TENANT_MAX     = 128;
    private const TRACE_MAX      = 128;
    private const PAYLOAD_MAX_B  = 2_000_000; // ~2MB soft limit

    public function __construct(
        public readonly string $eventType,
        #[\SensitiveParameter] public readonly string $payloadJson,
        public readonly ?string $aggregateTable = null,
        public readonly string|int|array|null $aggregateId = null,
        public readonly ?string $routingKey = null,
        public readonly ?string $tenant = null,
        public readonly ?string $traceId = null,
        public readonly ?array $crypto = null
    ) {
        // Minimal validation (BC-friendly): do not mutate, only validate.
        if (\trim($this->eventType) === '') {
            throw new \InvalidArgumentException('OutboxRecord: eventType must be a non-empty string.');
        }
        // JSON must be valid
        $this->assertJsonString($this->payloadJson);
    }

    // ---------------------------- Factories ----------------------------

    /**
     * Safely builds an OutboxRecord from an associative array (performs JSON encode).
     *
     * @param array<string,mixed> $payload
     */
    public static function fromPayloadArray(
        string $eventType,
        array $payload,
        ?string $aggregateTable = null,
        int|string|array|null $aggregateId = null,
        ?string $routingKey = null,
        ?string $tenant = null,
        ?string $traceId = null,
        ?array $crypto = null
    ): self {
        $eventType = self::safeEventType($eventType);
        $routingKey = self::safeOptString($routingKey, self::ROUTING_MAX);
        $tenant     = self::safeOptString($tenant, self::TENANT_MAX);
        $traceId    = self::safeOptString($traceId, self::TRACE_MAX);

        $json = self::encodeJson($payload);
        self::guardPayloadSize($json);

        return new self($eventType, $json, $aggregateTable, $aggregateId, $routingKey, $tenant, $traceId, $crypto);
    }

    /**
     * Conveniently wraps a domain `CrudEvent` for the outbox.
     * Payload carries `__type: "CrudEvent"` for easy reconstruction by consumers.
     */
    public static function fromCrudEvent(
        CrudEvent $e,
        ?string $routingKey = null,
        ?string $tenant = null,
        ?string $traceId = null
    ): self {
        $eventType = self::safeEventType('crud.' . $e->operation);
        $routingKey = self::safeOptString($routingKey ?? $e->table, self::ROUTING_MAX);
        $tenant     = self::safeOptString($tenant, self::TENANT_MAX);
        $traceId    = self::safeOptString($traceId, self::TRACE_MAX);

        $payload = [
            '__type'   => 'CrudEvent',
            'operation'=> $e->operation,
            'table'    => $e->table,
            'id'       => $e->id,
            'affected' => $e->affected,
            'before'   => $e->before,
            'after'    => $e->after,
            'context'  => $e->context,
        ];

        $json = self::encodeJson($payload);
        self::guardPayloadSize($json);

        $crypto = $e->context['crypto'] ?? null;
        return new self(
            eventType: $eventType,
            payloadJson: $json,
            aggregateTable: $e->table,
            aggregateId: $e->id,
            routingKey: $routingKey,
            tenant: $tenant,
            traceId: $traceId,
            crypto: \is_array($crypto) ? $crypto : null
        );
    }

    // ---------------------------- Helpers ----------------------------

    /** Normalized string identifying the aggregate PK – useful for logs/routing. */
    public function aggregateIdString(): ?string
    {
        $id = $this->aggregateId;
        if ($id === null) return null;
        if (\is_array($id)) {
            // Stable key ordering for consistent serialization
            if (self::isAssoc($id)) {
                \ksort($id);
            }
            return self::encodeJson($id);
        }
        return (string)$id;
    }

    /** Clone with a different routing key. */
    public function withRoutingKey(?string $routingKey): self
    {
        return new self(
            $this->eventType,
            $this->payloadJson,
            $this->aggregateTable,
            $this->aggregateId,
            self::safeOptString($routingKey, self::ROUTING_MAX),
            $this->tenant,
            $this->traceId
        );
    }

    /** Clone with a different tenant. */
    public function withTenant(?string $tenant): self
    {
        return new self(
            $this->eventType,
            $this->payloadJson,
            $this->aggregateTable,
            $this->aggregateId,
            $this->routingKey,
            self::safeOptString($tenant, self::TENANT_MAX),
            $this->traceId
        );
    }

    /** Clone with a different trace ID. */
    public function withTraceId(?string $traceId): self
    {
        return new self(
            $this->eventType,
            $this->payloadJson,
            $this->aggregateTable,
            $this->aggregateId,
            $this->routingKey,
            $this->tenant,
            self::safeOptString($traceId, self::TRACE_MAX)
        );
    }

    /** @return array<string,mixed> */
    public function toArray(): array
    {
        return [
            'eventType'      => $this->eventType,
            'payloadJson'    => $this->payloadJson,
            'aggregateTable' => $this->aggregateTable,
            'aggregateId'    => $this->aggregateId,
            'routingKey'     => $this->routingKey,
            'tenant'         => $this->tenant,
            'traceId'        => $this->traceId,
            'crypto'         => $this->crypto,
        ];
    }

    public function jsonSerialize(): array
    {
        return $this->toArray();
    }

    // --------------------- internal static utils ---------------------

    private static function safeEventType(string $s): string
    {
        $s = \trim($s);
        if ($s === '') {
            throw new \InvalidArgumentException('OutboxRecord: eventType must be non-empty.');
        }
        if (\strlen($s) > self::EVENT_TYPE_MAX) {
            $s = \substr($s, 0, self::EVENT_TYPE_MAX);
        }
        return $s;
    }

    private static function safeOptString(?string $s, int $max): ?string
    {
        if ($s === null) return null;
        $s = \trim($s);
        if ($s === '') return null;
        return \strlen($s) > $max ? \substr($s, 0, $max) : $s;
    }

    private static function encodeJson(mixed $value): string
    {
        $json = \json_encode($value, \JSON_UNESCAPED_UNICODE | \JSON_UNESCAPED_SLASHES);
        if ($json === false) {
            throw new \RuntimeException('OutboxRecord: JSON encoding failed: ' . \json_last_error_msg());
        }
        return $json;
    }

    private static function guardPayloadSize(string $json): void
    {
        if (\strlen($json) > self::PAYLOAD_MAX_B) {
            throw new \RuntimeException('OutboxRecord: payloadJson exceeds soft limit of ' . self::PAYLOAD_MAX_B . ' bytes.');
        }
    }

    private function assertJsonString(string $json): void
    {
        // Fast validation – decode without allocations (default depth); throw on error.
        \json_decode($json, true);
        if (\json_last_error() !== \JSON_ERROR_NONE) {
            throw new \InvalidArgumentException('OutboxRecord: payloadJson must be a valid JSON string.');
        }
    }

    private static function isAssoc(array $arr): bool
    {
        $i = 0;
        foreach ($arr as $k => $_) {
            if ($k !== $i++) {
                return true;
            }
        }
        return false;
    }
}
