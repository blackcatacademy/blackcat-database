<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Events;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Events\CrudEvent;
use BlackCat\Database\Events\NullCrudEventDispatcher;
use BlackCat\Database\Events\Psr14CrudEventDispatcher;
use BlackCat\Database\Events\CrudEventDispatcher;

final class CrudEventTest extends TestCase
{
    public function testConvenienceFlagsAndContext(): void
    {
        $event = new CrudEvent(CrudEvent::OP_CREATE, 'users', 1, context: ['corr' => 'abc']);
        $this->assertTrue($event->isCreate());
        $this->assertSame('abc', $event->correlationId());

        $bulk = CrudEvent::bulk('logs', 5)->withContext(['tenant' => 't']);
        $this->assertTrue($bulk->isBulk());
        $this->assertSame('t', $bulk->tenant());
        $this->assertSame('bulk', $bulk->operation);
    }

    public function testNullDispatcherIsSingleton(): void
    {
        $a = NullCrudEventDispatcher::instance();
        $b = NullCrudEventDispatcher::instance();
        $this->assertSame($a, $b);
        $a->dispatch(new CrudEvent(CrudEvent::OP_TOUCH, 't', null)); // no exceptions
        $this->assertInstanceOf(CrudEventDispatcher::class, $a);
    }

    public function testPsr14AdapterDispatchesGracefully(): void
    {
        $collector = new class {
            public array $events = [];
            public function dispatch(object $event): object { $this->events[] = $event; return $event; }
        };
        $dispatcher = Psr14CrudEventDispatcher::wrap($collector);
        $event = new CrudEvent(CrudEvent::OP_DELETE, 't', 1);
        $dispatcher->dispatch($event);
        $this->assertCount(1, $collector->events);

        // incompatible object falls back to Null dispatcher
        $noop = Psr14CrudEventDispatcher::wrap(null);
        $this->assertInstanceOf(CrudEventDispatcher::class, $noop);
    }
}
