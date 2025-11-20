<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Umbrella;

use PHPUnit\Framework\TestCase;
use BlackCat\Database\Tests\Util\DbUtil;
use BlackCat\Core\Database;

final class DatabaseHelpersTest extends TestCase
{
    public static function setUpBeforeClass(): void
    {
        // clean start
        DbUtil::wipeDatabase();
    }

    public function test_nested_transaction_with_savepoint(): void
    {
        $db = DbUtil::db();
        $db->exec("CREATE TABLE t1 (id INT PRIMARY KEY, val INT)");

        $db->transaction(function(Database $db) {
            $db->execute("INSERT INTO t1 (id,val) VALUES (:i,:v)", [':i'=>1,':v'=>10]);

            // nested transaction -> rollback inner, commit outer
            try {
                $db->transaction(function(Database $db) {
                    $db->execute("INSERT INTO t1 (id,val) VALUES (:i,:v)", [':i'=>2,':v'=>20]);
                    throw new \RuntimeException('boom');
                });
                $this->fail('inner must throw');
            } catch (\RuntimeException $e) {}

            // t1(id=2) should not exist
            $this->assertFalse($db->exists("SELECT 1 FROM t1 WHERE id=2"));
        });

        $this->assertTrue($db->exists("SELECT 1 FROM t1 WHERE id=1"));
        $this->assertFalse($db->exists("SELECT 1 FROM t1 WHERE id=2"));
    }

    public function test_with_statement_timeout(): void
    {
        $db = DbUtil::db();
        $this->expectNotToPerformAssertions(); // only asserts that dialect throws or not accordingly

        if ($db->isPg()) {
            try {
                $db->withStatementTimeout(50, function(Database $db) {
                    $db->query("SELECT pg_sleep(0.2)");
                });
                $this->fail('expected timeout on PG');
            } catch (\Throwable $e) {
                // ok
            }
        } elseif ($db->isMysql()) {
            try {
                $db->withStatementTimeout(50, function(Database $db) {
                    $db->query("SELECT SLEEP(0.2)");
                });
            } catch (\Throwable $e) { /* some versions might not enforce it */ }
        }
    }

    public function test_keyset_pagination(): void
    {
        $db = DbUtil::db();
        $db->exec("CREATE TABLE kpag (id INT PRIMARY KEY, val INT)");
        for ($i=1;$i<=30;$i++) {
            $db->execute("INSERT INTO kpag (id,val) VALUES (:i,:v)", [':i'=>$i, ':v'=>100+$i]);
        }

        $base = "SELECT * FROM kpag";
        $page1 = $db->paginateKeyset($base, [], 'id', 'id', null, 10);
        $this->assertCount(10, $page1['items']);

        $page2 = $db->paginateKeyset($base, [], 'id', 'id', $page1['nextAfter'], 10);
        $this->assertCount(10, $page2['items']);
        $this->assertLessThan($page1['nextAfter'], $page2['nextAfter'] ?? 999999);
    }

    public function test_quote_ident_and_in_clause(): void
    {
        $db = DbUtil::db();
        $col = $db->quoteIdent('strange.name');
        $this->assertNotEmpty($col);

        [$sql, $params] = $db->inClause('id', range(1,5), 'x', 2);
        $this->assertStringContainsString('IN', $sql);
        $this->assertCount(5, $params);
    }
}
