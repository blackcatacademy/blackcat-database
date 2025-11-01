<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class ViewsComputedColumnsBehaviorTest extends TestCase
{
    private static function db(): Database { return Database::getInstance(); }

    protected function setUp(): void { self::db()->exec('START TRANSACTION'); }
    protected function tearDown(): void { self::db()->exec('ROLLBACK'); }

    public function test_sessions_is_active(): void
    {
        $db = self::db();
        $db->exec("INSERT INTO users (password_hash,is_active,actor_role) VALUES ('x',1,'customer')");
        $uid = (int)$db->fetchOne("SELECT LAST_INSERT_ID()");

        $db->exec("INSERT INTO sessions (token_hash,user_id,revoked,expires_at,last_seen_at)
                   VALUES (UNHEX(REPEAT('aa',32)),?,0,NOW()+INTERVAL 1 HOUR,NOW())", [$uid]);
        $db->exec("INSERT INTO sessions (token_hash,user_id,revoked,expires_at,last_seen_at)
                   VALUES (UNHEX(REPEAT('bb',32)),?,1,NOW()+INTERVAL 1 HOUR,NOW())", [$uid]);
        $db->exec("INSERT INTO sessions (token_hash,user_id,revoked,expires_at,last_seen_at)
                   VALUES (UNHEX(REPEAT('cc',32)),?,0,NOW()-INTERVAL 1 MINUTE,NOW())", [$uid]);

        $rows = $db->fetchAll("SELECT is_active FROM vw_sessions ORDER BY id ASC");
        $actives = array_sum(array_map(fn($r)=> (int)$r['is_active'], $rows));
        $this->assertSame(1, $actives, 'Exactly one active session expected');
    }

    public function test_coupons_is_current(): void
    {
        $db = self::db();
        $db->exec("INSERT INTO coupons (code,type,value,currency,starts_at,ends_at,is_active)
                   VALUES ('NOWPCT','percent',10,NULL, CURDATE()-INTERVAL 1 DAY, CURDATE()+INTERVAL 1 DAY, 1)");
        $db->exec("INSERT INTO coupons (code,type,value,currency,starts_at,ends_at,is_active)
                   VALUES ('EXPIRED','percent',10,NULL, CURDATE()-INTERVAL 3 DAY, CURDATE()-INTERVAL 1 DAY, 1)");
        $db->exec("INSERT INTO coupons (code,type,value,currency,starts_at,ends_at,is_active)
                   VALUES ('INACTIVE','percent',10,NULL, CURDATE()-INTERVAL 1 DAY, CURDATE()+INTERVAL 1 DAY, 0)");

        $rows = $db->fetchAll("SELECT code, is_current FROM vw_coupons ORDER BY id ASC");
        $m = [];
        foreach ($rows as $r) { $m[$r['code']] = (int)$r['is_current']; }

        $this->assertSame(1, $m['NOWPCT'] ?? 0);
        $this->assertSame(0, $m['EXPIRED'] ?? 1);
        $this->assertSame(0, $m['INACTIVE'] ?? 1);
    }

    public function test_idempotency_keys_expiry_helpers(): void
    {
        $db = self::db();
        $db->exec("INSERT INTO idempotency_keys (key_hash, created_at, ttl_seconds)
                   VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', NOW(), 2)");
        $db->exec("INSERT INTO idempotency_keys (key_hash, created_at, ttl_seconds)
                   VALUES ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', NOW()-INTERVAL 10 SECOND, 2)");

        $rows = $db->fetchAll("SELECT key_hash, is_expired FROM vw_idempotency_keys ORDER BY key_hash ASC");
        $m = [];
        foreach ($rows as $r) { $m[$r['key_hash']] = (int)$r['is_expired']; }

        $this->assertSame(0, $m['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'] ?? 1);
        $this->assertSame(1, $m['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'] ?? 0);
    }

    public function test_order_item_downloads_helpers(): void
    {
        $db = self::db();
        // seed author/category/book
        $db->exec("INSERT INTO authors (name,slug) VALUES ('A','a')");
        $aid = (int)$db->fetchOne("SELECT LAST_INSERT_ID()");
        $db->exec("INSERT INTO categories (name,slug) VALUES ('C','c')");
        $cid = (int)$db->fetchOne("SELECT LAST_INSERT_ID()");
        $db->exec("INSERT INTO books (title,slug,author_id,main_category_id,price,currency) VALUES ('B','b',?,?,10,'EUR')", [$aid,$cid]);

        $db->exec("INSERT INTO orders (uuid,currency,total) VALUES (UUID(),'EUR',10.00)");
        $oid = (int)$db->fetchOne("SELECT LAST_INSERT_ID()");
        $bookId = (int)$db->fetchOne("SELECT id FROM books WHERE slug='b'");
        $db->exec("INSERT INTO book_assets (book_id,asset_type,filename,mime_type,size_bytes) VALUES (?,?, 'f','application/pdf',1)", [$bookId,'pdf']);
        $assetId = (int)$db->fetchOne("SELECT LAST_INSERT_ID()");

        $db->exec("INSERT INTO order_item_downloads (order_id,book_id,asset_id,max_uses,used,expires_at)
                   VALUES (?,?,?,5,2,NOW()+INTERVAL 1 HOUR)", [$oid,$bookId,$assetId]);

        $row = $db->fetchAll("SELECT uses_left,is_valid FROM vw_order_item_downloads WHERE order_id=?", [$oid])[0] ?? null;
        $this->assertNotNull($row);
        $this->assertSame(3, (int)$row['uses_left']);
        $this->assertSame(1, (int)$row['is_valid']);
    }

    public function test_system_errors_ip_helpers(): void
    {
        $db = self::db();
        $db->exec("INSERT INTO system_errors (level,message,ip_bin) VALUES ('notice','x', INET6_ATON('127.0.0.1'))");
        $row = $db->fetchAll("SELECT ip_bin_hex, ip_pretty FROM vw_system_errors ORDER BY id DESC LIMIT 1")[0] ?? null;
        $this->assertNotNull($row);
        $this->assertSame(32, strlen((string)$row['ip_bin_hex']));
        $this->assertSame('127.0.0.1', (string)$row['ip_pretty']);
    }
}
