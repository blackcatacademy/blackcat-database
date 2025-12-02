<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class ViewsComputedColumnsBehaviorTest extends TestCase
{
    private static ?int $baseTenantId = null;
    private static function db(): Database { return Database::getInstance(); }

    public static function setUpBeforeClass(): void
    {
        $db = self::db();
        // Seed one committed tenant for FK convenience
        $db->exec("INSERT INTO tenants (name, slug) VALUES ('Test Tenant','tenant-base')");
        self::$baseTenantId = (int)$db->fetchOne("SELECT LAST_INSERT_ID()");
    }

    private static function ensureTenant(): int
    {
        if (self::$baseTenantId !== null) {
            return self::$baseTenantId;
        }
        $db = self::db();
        $db->exec("INSERT INTO tenants (name, slug) VALUES ('Test Tenant','tenant-auto')");
        return (int)$db->fetchOne("SELECT LAST_INSERT_ID()");
    }

    protected function setUp(): void { self::db()->exec('START TRANSACTION'); }
    protected function tearDown(): void { self::db()->exec('ROLLBACK'); }

    public function test_sessions_is_active(): void
    {
        $db = self::db();
        $isPg = $db->isPg();

        if ($isPg) {
            $uid = (int)$db->fetchOne(
                "INSERT INTO users (password_hash,is_active,actor_role)
                VALUES ('x', TRUE, 'customer')
                RETURNING id"
            );

            $db->exec(
                "INSERT INTO sessions (token_hash,user_id,revoked,expires_at,last_seen_at)
                VALUES (decode(repeat('aa',32), 'hex'), ?, FALSE, now() + interval '1 hour', now())",
                [$uid]
            );
            $db->exec(
                "INSERT INTO sessions (token_hash,user_id,revoked,expires_at,last_seen_at)
                VALUES (decode(repeat('bb',32), 'hex'), ?, TRUE,  now() + interval '1 hour', now())",
                [$uid]
            );
        } else {
            $db->exec("INSERT INTO users (password_hash,is_active,actor_role) VALUES ('x',1,'customer')");
            $uid = (int)$db->fetchOne("SELECT LAST_INSERT_ID()");
            $db->exec("INSERT INTO sessions (token_hash,user_id,revoked,expires_at,last_seen_at)
                    VALUES (UNHEX(REPEAT('aa',32)),?,0,NOW()+INTERVAL 1 HOUR,NOW())", [$uid]);
            $db->exec("INSERT INTO sessions (token_hash,user_id,revoked,expires_at,last_seen_at)
                    VALUES (UNHEX(REPEAT('bb',32)),?,1,NOW()+INTERVAL 1 HOUR,NOW())", [$uid]);
        }

        $rows = $db->fetchAll("SELECT is_active FROM vw_sessions ORDER BY id ASC");
        $actives = array_sum(array_map(fn($r)=> (int)$r['is_active'], $rows));
        $this->assertSame(1, $actives, 'Exactly one active session expected');
    }

    public function test_coupons_is_current(): void
    {
        $db = self::db();
        $tid = self::ensureTenant();
        if ($db->isPg()) {
            $db->exec("INSERT INTO coupons (tenant_id,code,type,value,currency,starts_at,ends_at,is_active)
                    VALUES ($tid,'NOWPCT','percent',10,NULL, current_date - interval '1 day', current_date + interval '1 day', TRUE)");
            $db->exec("INSERT INTO coupons (tenant_id,code,type,value,currency,starts_at,ends_at,is_active)
                    VALUES ($tid,'EXPIRED','percent',10,NULL, current_date - interval '3 day', current_date - interval '1 day', TRUE)");
            $db->exec("INSERT INTO coupons (tenant_id,code,type,value,currency,starts_at,ends_at,is_active)
                    VALUES ($tid,'INACTIVE','percent',10,NULL, current_date - interval '1 day', current_date + interval '1 day', FALSE)");
        } else {
            $db->exec("INSERT INTO coupons (tenant_id,code,type,value,currency,starts_at,ends_at,is_active)
                    VALUES ($tid,'NOWPCT','percent',10,NULL, CURDATE()-INTERVAL 1 DAY, CURDATE()+INTERVAL 1 DAY, 1)");
            $db->exec("INSERT INTO coupons (tenant_id,code,type,value,currency,starts_at,ends_at,is_active)
                    VALUES ($tid,'EXPIRED','percent',10,NULL, CURDATE()-INTERVAL 3 DAY, CURDATE()-INTERVAL 1 DAY, 1)");
            $db->exec("INSERT INTO coupons (tenant_id,code,type,value,currency,starts_at,ends_at,is_active)
                    VALUES ($tid,'INACTIVE','percent',10,NULL, CURDATE()-INTERVAL 1 DAY, CURDATE()+INTERVAL 1 DAY, 0)");
        }

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
        $tid = self::ensureTenant();
        if ($db->isPg()) {
            $db->exec("INSERT INTO idempotency_keys (key_hash, tenant_id, created_at, ttl_seconds)
                    VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', $tid, now(), 2)");
            $db->exec("INSERT INTO idempotency_keys (key_hash, tenant_id, created_at, ttl_seconds)
                    VALUES ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', $tid, now() - interval '10 seconds', 2)");
        } else {
            $db->exec("INSERT INTO idempotency_keys (key_hash, tenant_id, created_at, ttl_seconds)
                    VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', $tid, NOW(), 2)");
            $db->exec("INSERT INTO idempotency_keys (key_hash, tenant_id, created_at, ttl_seconds)
                    VALUES ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', $tid, NOW()-INTERVAL 10 SECOND, 2)");
        }

        $rows = $db->fetchAll("SELECT key_hash, is_expired FROM vw_idempotency_keys ORDER BY key_hash ASC");
        $m = [];
        foreach ($rows as $r) { $m[$r['key_hash']] = (int)$r['is_expired']; }
        $this->assertSame(0, $m['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'] ?? 1);
        $this->assertSame(1, $m['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'] ?? 0);
    }

    public function test_order_item_downloads_helpers(): void
    {
        $db = self::db();
        $isPg = $db->isPg();
        $tid = self::ensureTenant();

        // authors
        $aid = $isPg
            ? (int)$db->fetchOne("INSERT INTO authors (tenant_id,name,slug) VALUES ($tid,'A','a') RETURNING id")
            : (function() use($db,$tid){ $db->exec("INSERT INTO authors (tenant_id,name,slug) VALUES ($tid,'A','a')"); return (int)$db->fetchOne("SELECT LAST_INSERT_ID()"); })();

        // categories
        $cid = $isPg
            ? (int)$db->fetchOne("INSERT INTO categories (tenant_id,name,slug) VALUES ($tid,'C','c') RETURNING id")
            : (function() use($db,$tid){ $db->exec("INSERT INTO categories (tenant_id,name,slug) VALUES ($tid,'C','c')"); return (int)$db->fetchOne("SELECT LAST_INSERT_ID()"); })();

        // books
        $db->exec("INSERT INTO books (tenant_id,title,slug,author_id,main_category_id,price,currency) VALUES ($tid,'B','b',?,?,10,'EUR')", [$aid,$cid]);
        $bookId = (int)$db->fetchOne("SELECT id FROM books WHERE slug='b'");

        // orders
        $oid = $isPg
            ? (int)$db->fetchOne("INSERT INTO orders (tenant_id,uuid,currency,subtotal,discount_total,tax_total,total) VALUES ($tid,'00000000-0000-0000-0000-000000000000','EUR',10.00,0,0,10.00) RETURNING id")
            : (function() use($db,$tid){ $db->exec("INSERT INTO orders (tenant_id,uuid,currency,subtotal,discount_total,tax_total,total) VALUES ($tid,UUID(),'EUR',10.00,0,0,10.00)"); return (int)$db->fetchOne("SELECT LAST_INSERT_ID()"); })();

        // book_assets
        $assetId = $isPg
            ? (int)$db->fetchOne("INSERT INTO book_assets (tenant_id,book_id,asset_type,filename,mime_type,size_bytes) VALUES ($tid,?,?,'f','application/pdf',1) RETURNING id", [$bookId,'pdf'])
            : (function() use($db,$bookId,$tid){ $db->exec("INSERT INTO book_assets (tenant_id,book_id,asset_type,filename,mime_type,size_bytes) VALUES ($tid,?,?,'f','application/pdf',1)", [$bookId,'pdf']); return (int)$db->fetchOne("SELECT LAST_INSERT_ID()"); })();

        // order_item_downloads
        if ($isPg) {
            $db->exec(
                "INSERT INTO order_item_downloads (tenant_id,order_id,book_id,asset_id,max_uses,used,expires_at)
                VALUES ($tid,?,?,?,5,2, now() + interval '1 hour')", [$oid,$bookId,$assetId]
            );
        } else {
            $db->exec(
                "INSERT INTO order_item_downloads (tenant_id,order_id,book_id,asset_id,max_uses,used,expires_at)
                VALUES ($tid,?,?,?,5,2,NOW()+INTERVAL 1 HOUR)", [$oid,$bookId,$assetId]
            );
        }

        $row = $db->fetchAll("SELECT uses_left,is_valid FROM vw_order_item_downloads WHERE order_id=?", [$oid])[0] ?? null;
        $this->assertNotNull($row);
        $this->assertSame(3, (int)$row['uses_left']);
        $this->assertSame(1, (int)$row['is_valid']);
    }

    public function test_system_errors_ip_helpers(): void
    {
        $db = self::db();
        if ($db->isPg()) {
            // IPv4-mapped value stored in 16 bytes -> hex length 32, pretty prints as 127.0.0.1
            $db->exec("INSERT INTO system_errors (level,message,ip_bin)
                    VALUES ('notice','x', decode('00000000000000000000ffff7f000001','hex'))");
        } else {
            $db->exec("INSERT INTO system_errors (level,message,ip_bin)
                    VALUES ('notice','x', INET6_ATON('127.0.0.1'))");
        }

        $row = $db->fetchAll("SELECT ip_bin_hex, ip_pretty FROM vw_system_errors ORDER BY id DESC LIMIT 1")[0] ?? null;
        $this->assertNotNull($row);
        $this->assertSame(32, strlen((string)$row['ip_bin_hex']));
        $this->assertSame('127.0.0.1', (string)$row['ip_pretty']);
    }
}
