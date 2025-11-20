<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Outbox\OutboxRepository;
use BlackCat\Database\Outbox\OutboxRecord;
use BlackCat\Database\Outbox\OutboxConsumer;
use BlackCat\Database\Events\CrudEventDispatcher;
use BlackCat\Database\Events\CrudEvent;
use RuntimeException;

final class OutboxConsumerTest extends TestCase
{
    private static Database $db;

    public static function setUpBeforeClass(): void
    {
        self::$db = Database::getInstance();
        self::recreateTable();
    }

    protected function setUp(): void
    {
        self::$db->exec('DELETE FROM bc_outbox_events');
    }

    private static function recreateTable(): void
    {
        $db = Database::getInstance();
        $dial = $db->dialect();
        $db->exec('DROP TABLE IF EXISTS bc_outbox_events');
        if ($dial->isPg()) {
            $db->exec('CREATE TABLE bc_outbox_events (
                id bigserial PRIMARY KEY,
                created_at timestamptz(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                available_at timestamptz(6) NOT NULL,
                event_type text NOT NULL,
                payload jsonb NOT NULL,
                routing_key text NULL,
                tenant text NULL,
                trace_id text NULL,
                acked_at timestamptz(6) NULL,
                fail_count int NOT NULL DEFAULT 0,
                last_error text NULL
            )');
        } else {
            $db->exec('CREATE TABLE bc_outbox_events (
                id bigint PRIMARY KEY AUTO_INCREMENT,
                created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                available_at TIMESTAMP(6) NOT NULL,
                event_type VARCHAR(128) NOT NULL,
                payload JSON NOT NULL,
                routing_key VARCHAR(255) NULL,
                tenant VARCHAR(128) NULL,
                trace_id VARCHAR(128) NULL,
                acked_at TIMESTAMP(6) NULL,
                fail_count INT NOT NULL DEFAULT 0,
                last_error TEXT NULL
            )');
        }
    }

    private function repo(): OutboxRepository
    {
        return new OutboxRepository(self::$db);
    }

    public function testRunOnceDispatchesAndAcks(): void
    {
        $repo = $this->repo();
        $record = OutboxRecord::fromPayloadArray('demo', ['foo' => 'bar']);
        $repo->insert($record);

        $dispatcher = new class implements CrudEventDispatcher {
            public array $events = [];
            public function dispatch(CrudEvent $event): void { $this->events[] = $event; }
        };

        $consumer = new OutboxConsumer(self::$db, $repo, $dispatcher);
        $acked = $consumer->runOnce(5);
        $this->assertSame(1, $acked);
        $this->assertCount(1, $dispatcher->events);
    }

    public function testRunOnceMarksRowFailedOnDispatcherException(): void
    {
        $repo = $this->repo();
        $record = OutboxRecord::fromPayloadArray('demo', ['foo' => 'bar']);
        $repo->insert($record);

        $dispatcher = new class implements CrudEventDispatcher {
            public function dispatch(CrudEvent $event): void { throw new RuntimeException('boom'); }
        };

        $consumer = new OutboxConsumer(self::$db, $repo, $dispatcher);
        $acked = $consumer->runOnce(5);
        $this->assertSame(0, $acked);
        $row = self::$db->fetch('SELECT fail_count FROM bc_outbox_events LIMIT 1');
        $this->assertSame(1, (int)$row['fail_count']);
    }
}
