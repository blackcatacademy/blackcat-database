<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Outbox\OutboxRecord;
use BlackCat\Database\Events\CrudEvent;

final class OutboxRecordTest extends TestCase
{
    public function testFromPayloadArrayNormalizesMetadata(): void
    {
        $rec = OutboxRecord::fromPayloadArray('user.created', ['id' => 1], routingKey: ' users ', tenant: 'TEN', traceId: 'TRACE');
        $this->assertSame('user.created', $rec->eventType);
        $this->assertSame('users', $rec->routingKey);
        $this->assertSame('TEN', $rec->tenant);
        $this->assertSame('TRACE', $rec->traceId);
        $this->assertSame('"id":1', $rec->payloadJson);
    }

    public function testFromCrudEventCopiesAggregate(): void
    {
        $event = new CrudEvent(CrudEvent::OP_UPDATE, 'users', ['id' => 5], 1);
        $rec = OutboxRecord::fromCrudEvent($event, routingKey: 'users');
        $this->assertSame('crud.update', $rec->eventType);
        $this->assertSame('users', $rec->aggregateTable);
        $this->assertSame('5', $rec->aggregateIdString());
    }

    public function testAggregateIdStringHandlesComposite(): void
    {
        $rec = new OutboxRecord('x', json_encode(['ok' => true]) ?: '{}', aggregateTable: 't', aggregateId: ['b' => 2, 'a' => 1]);
        $this->assertSame('{"a":1,"b":2}', $rec->aggregateIdString());
    }

    public function testWithRoutingTenantTrace(): void
    {
        $rec = new OutboxRecord('evt', '{}');
        $next = $rec->withRoutingKey('key')->withTenant('tenant')->withTraceId('trace');
        $this->assertSame('key', $next->routingKey);
        $this->assertSame('tenant', $next->tenant);
        $this->assertSame('trace', $next->traceId);
    }
}
