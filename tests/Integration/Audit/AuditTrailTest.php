<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Audit\AuditTrail;

final class AuditTrailTest extends TestCase
{
    private static Database $db;

    protected function setUp(): void
    {
        self::$db = Database::getInstance();
        self::$db->exec('DROP TABLE IF EXISTS audit_changes');
        self::$db->exec('DROP TABLE IF EXISTS audit_tx');
    }

    public function testRecordAndPurge(): void
    {
        $audit = new AuditTrail(self::$db, 'audit_changes', 'audit_tx');
        $audit->installSchema();

        $audit->record('users', 1, 'insert', ['name' => 'old'], ['name' => 'new'], 'tester');
        $audit->recordDiff('users', 1, ['name' => 'old'], ['name' => 'new']);
        $audit->recordTx('begin', ['svc' => 'test']);

        $cnt = (int)self::$db->fetchOne('SELECT COUNT(*) FROM audit_changes');
        $this->assertSame(2, $cnt);
        $txCnt = (int)self::$db->fetchOne('SELECT COUNT(*) FROM audit_tx');
        $this->assertSame(1, $txCnt);

        // age rows and ensure purge removes them
        if (self::$db->dialect()->isPg()) {
            self::$db->exec("UPDATE audit_changes SET ts = CURRENT_TIMESTAMP - INTERVAL '10 days'");
        } else {
            self::$db->exec("UPDATE audit_changes SET ts = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 10 DAY)");
        }
        $deleted = $audit->purgeOlderThanDays(5);
        $this->assertGreaterThanOrEqual(1, $deleted);
    }
}
