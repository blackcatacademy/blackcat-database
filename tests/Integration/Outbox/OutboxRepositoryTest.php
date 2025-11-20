<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Outbox\OutboxRepository;
use BlackCat\Database\Outbox\OutboxRecord;

final class OutboxRepositoryTest extends TestCase
{
    private static Database $db;

    public static function setUpBeforeClass(): void
    {
        self::$db = Database::getInstance();
        self::recreateTable();
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

    public function testInsertClaimAckAndCleanup(): void
    {
        $repo = $this->repo();
        $record = OutboxRecord::fromPayloadArray('demo', ['foo' => 'bar']);
        $repo->insert($record);

        $batch = $repo->claimBatch(5);
        $this->assertCount(1, $batch);
        $id = (int)$batch[0]['id'];
        $this->assertIsString($batch[0]['payload']);

        $repo->ack($id);
        $row = self::$db->fetch('SELECT acked_at FROM bc_outbox_events WHERE id = :id', [':id' => $id]);
        $this->assertNotNull($row['acked_at'] ?? null);

        $repo->fail($id, 'error', 1);
        $row2 = self::$db->fetch('SELECT fail_count, last_error FROM bc_outbox_events WHERE id = :id', [':id' => $id]);
        $this->assertSame(1, (int)$row2['fail_count']);

        // mark acked row as old and ensure cleanup removes it
        if (self::$db->dialect()->isPg()) {
            self::$db->exec("UPDATE bc_outbox_events SET available_at = CURRENT_TIMESTAMP - INTERVAL '10 days', acked_at = CURRENT_TIMESTAMP - INTERVAL '10 days' WHERE id = :id", [':id' => $id]);
        } else {
            self::$db->exec("UPDATE bc_outbox_events SET available_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 10 DAY), acked_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 10 DAY) WHERE id = :id", [':id' => $id]);
        }
        $deleted = $repo->cleanup(100, 24 * 3600);
        $this->assertGreaterThanOrEqual(1, $deleted);
    }
}
