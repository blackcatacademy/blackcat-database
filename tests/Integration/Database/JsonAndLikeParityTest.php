<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;

final class JsonAndLikeParityTest extends TestCase
{
    public function test_json_contains_and_extract(): void
    {
        $db = Database::getInstance();
        $db->exec("DROP TABLE IF EXISTS js");
        $db->exec($db->isPg()
            ? "CREATE TABLE js (id BIGSERIAL PRIMARY KEY, payload JSONB NOT NULL)"
            : "CREATE TABLE js (id BIGINT PRIMARY KEY AUTO_INCREMENT, payload JSON NOT NULL)");

        $db->exec("INSERT INTO js(payload) VALUES (:j)", [':j'=>json_encode(['a'=>1,'b'=>['c'=>'x']])]);

        if ($db->isPg()) {
            $cnt = (int)$db->fetchOne("SELECT COUNT(*) FROM js WHERE payload @> :n::jsonb", [':n'=>'{"a":1}']);
            $c   = (string)$db->fetchOne("SELECT payload->'b'->>'c' FROM js LIMIT 1");
        } else {
            $cnt = (int)$db->fetchOne("SELECT COUNT(*) FROM js WHERE JSON_CONTAINS(payload, JSON_OBJECT('a',1))");
            $c   = (string)$db->fetchOne("SELECT JSON_UNQUOTE(JSON_EXTRACT(payload,'$.b.c')) FROM js LIMIT 1");
        }
        $this->assertSame(1, $cnt);
        $this->assertSame('x', $c);
    }

    public function test_like_escapes_wildcards(): void
    {
        $db = Database::getInstance();
        $db->exec("DROP TABLE IF EXISTS t");
        $db->exec($db->isPg()
            ? "CREATE TABLE t (id BIGSERIAL PRIMARY KEY, v TEXT)"
            : "CREATE TABLE t (id BIGINT PRIMARY KEY AUTO_INCREMENT, v VARCHAR(100))");
        $db->exec("INSERT INTO t(v) VALUES ('foo%bar_'), ('FoO%BaR_'), ('zzz')");

        $needle = 'foo%bar_';
        $like = '%' . strtr($needle, ['\\'=>'\\\\','%'=>'\\%','_'=>'\\_']) . '%';
        $sql = $db->isPg() ? "SELECT COUNT(*) FROM t WHERE v ILIKE :q ESCAPE '\\\\'"
                           : "SELECT COUNT(*) FROM t WHERE v LIKE :q ESCAPE '\\\\'";
        $cnt = (int)$db->fetchOne($sql, [':q'=>$like]);
        $this->assertGreaterThanOrEqual(1, $cnt);
    }
}
