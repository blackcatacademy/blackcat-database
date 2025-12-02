<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Idempotency\PdoIdempotencyStore;
use BlackCat\Core\Database;

final class PdoIdempotencyStoreTest extends TestCase
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
        $db->exec('DROP TABLE IF EXISTS bc_idempotency');
        if ($dial->isPg()) {
            $db->exec('CREATE TABLE bc_idempotency (
                id_key text PRIMARY KEY,
                status text NOT NULL,
                result_json jsonb NULL,
                created_at timestamptz(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                updated_at timestamptz(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
            )');
        } else {
            $db->exec('CREATE TABLE bc_idempotency (
                id_key varchar(191) PRIMARY KEY,
                status varchar(32) NOT NULL,
                result_json JSON NULL,
                created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
            )');
        }
    }

    public function testBeginCommitFailAndPurge(): void
    {
        $store = new PdoIdempotencyStore(self::$db);
        $this->assertTrue($store->begin('op-1'));
        $this->assertFalse($store->begin('op-1'));
        $store->commit('op-1', ['ok' => true]);
        $rec = $store->get('op-1');
        $this->assertIsArray($rec);
        $this->assertSame('success', $rec['status']);
        $this->assertArrayHasKey('result', $rec);
        $this->assertSame(['ok' => true], $rec['result']);

        $this->assertTrue($store->begin('op-2'));
        $store->fail('op-2', 'boom');
        $rec2 = $store->get('op-2');
        $this->assertIsArray($rec2);
        $this->assertSame('failed', $rec2['status']);

        // make op-2 older than threshold
        if (self::$db->dialect()->isPg()) {
            self::$db->exec("UPDATE bc_idempotency SET updated_at = CURRENT_TIMESTAMP - INTERVAL '10 days'");
        } else {
            self::$db->exec("UPDATE bc_idempotency SET updated_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 10 DAY)");
        }

        $purged = $store->purgeOlderThan(new DateInterval('P5D'));
        $this->assertGreaterThanOrEqual(1, $purged);
    }
}
