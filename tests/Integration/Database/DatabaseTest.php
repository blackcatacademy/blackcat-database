<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Integration\Database;

use PHPUnit\Framework\TestCase;

// Polyfills in case tests run without them (or a different autoloader):
if (!interface_exists('\Psr\Log\LoggerInterface')) {
    interface LoggerInterface {
        public function emergency($message, array $context = []);
        public function alert($message, array $context = []);
        public function critical($message, array $context = []);
        public function error($message, array $context = []);
        public function warning($message, array $context = []);
        public function notice($message, array $context = []);
        public function info($message, array $context = []);
        public function debug($message, array $context = []);
        public function log($level, $message, array $context = []);
    }
} else {
    interface LoggerInterface extends \Psr\Log\LoggerInterface {}
}

if (!interface_exists('\BlackCat\Database\Support\QueryObserver')) {
    interface QueryObserver {
        public function onQueryStart(string $sql, array $params, string $route): void;
        public function onQueryEnd(string $sql, array $params, ?float $ms, ?\Throwable $err, string $route): void;
    }
} else {
    interface QueryObserver extends \BlackCat\Database\Support\QueryObserver {}
}

use BlackCat\Core\Database;
use BlackCat\Core\DatabaseException;
use BlackCat\Core\DeadlockException;
use BlackCat\Core\LockTimeoutException;
use BlackCat\Core\SerializationFailureException;
use BlackCat\Core\ConnectionGoneException;

final class SpyLogger implements LoggerInterface
{
    /** @var list<array{level:string,msg:string,ctx:array}> */
    public array $lines = [];

    public function log($level, $message, array $context = []): void {
        $this->lines[] = ['level'=>(string)$level, 'msg'=>(string)$message, 'ctx'=>$context];
    }
    public function emergency($message, array $context = []): void { $this->log('emergency', $message, $context); }
    public function alert($message, array $context = []): void     { $this->log('alert', $message, $context); }
    public function critical($message, array $context = []): void  { $this->log('critical', $message, $context); }
    public function error($message, array $context = []): void     { $this->log('error', $message, $context); }
    public function warning($message, array $context = []): void   { $this->log('warning', $message, $context); }
    public function notice($message, array $context = []): void    { $this->log('notice', $message, $context); }
    public function info($message, array $context = []): void      { $this->log('info', $message, $context); }
    public function debug($message, array $context = []): void     { $this->log('debug', $message, $context); }

    /** @param null|callable(array):bool $filter */
    public function pop(callable|null $filter = null): array {
        return $this->lines;
    }
    public function has(callable $pred): bool {
        foreach ($this->lines as $l) if ($pred($l)) return true;
        return false;
    }
}

final class TestObserver implements QueryObserver
{
    /** @var list<array{phase:string,route:string,sql:string,ms?:float,err?:string}> */
    public array $events = [];
    public function onQueryStart(string $sql, array $params, string $route): void {
        $this->events[] = ['phase'=>'start','route'=>$route,'sql'=>$sql];
    }
    public function onQueryEnd(string $sql, array $params, ?float $ms, ?\Throwable $err, string $route): void {
        $rec = ['phase'=>'end','route'=>$route,'sql'=>$sql];
        if ($ms !== null) $rec['ms'] = $ms;
        if ($err !== null) $rec['err'] = $err->getMessage();
        $this->events[] = $rec;
    }
}

final class DatabaseTest extends TestCase
{
    private static ?Database $db = null;
    private static SpyLogger $logger;

    public static function setUpBeforeClass(): void
    {
        self::$logger = new SpyLogger();

        if (!Database::isInitialized()) {
            Database::init(self::configFromEnv(), self::$logger);
        }
        self::$db = Database::getInstance();
        self::$db->setLogger(self::$logger);
        self::ensureSchema(self::$db);
    }

    protected function setUp(): void
    {
        $this->assertNotNull(self::$db);
        // idempotent cleanup of test data
        self::truncateAll(self::$db);
    }

    /** Helpery */

    private static function ensureSchema(Database $db): void
    {
        $drv = $db->driver();
        if ($drv === 'mysql') {
            $db->exec('CREATE TABLE IF NOT EXISTS items (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100) UNIQUE,
                val INT
            )');
            $db->exec('CREATE TABLE IF NOT EXISTS kv (
                k VARCHAR(64) PRIMARY KEY,
                v INT NOT NULL
            )');
        } elseif ($drv === 'pgsql') {
            $db->exec('CREATE TABLE IF NOT EXISTS items (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) UNIQUE,
                val INT
            )');
            $db->exec('CREATE TABLE IF NOT EXISTS kv (
                k VARCHAR(64) PRIMARY KEY,
                v INT NOT NULL
            )');
        } else { // sqlite
            $db->exec('CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE,
                val INTEGER
            )');
            $db->exec('CREATE TABLE IF NOT EXISTS kv (
                k TEXT PRIMARY KEY,
                v INTEGER NOT NULL
            )');
        }
        // ensure a deterministic baseline even if tables already exist
        self::truncateAll($db);
    }

    private static function truncateAll(Database $db): void
    {
        $drv = $db->driver();
        if ($drv === 'pgsql') {
            $db->exec('TRUNCATE TABLE items RESTART IDENTITY CASCADE');
            $db->exec('TRUNCATE TABLE kv');
        } else {
            $db->exec('DELETE FROM items');
            $db->exec('DELETE FROM kv');
            if ($drv === 'sqlite') {
                $db->exec("DELETE FROM sqlite_sequence WHERE name IN ('items','kv')");
            }
        }
        // re-seed
        $db->insertMany('items', [
            ['name'=>'a','val'=>1],
            ['name'=>'b','val'=>2],
            ['name'=>'c','val'=>3],
        ]);
    }

    private static function resetSingleton(): void
    {
        \Closure::bind(function() { Database::$instance = null; }, null, Database::class)();
    }

    private static function resetCircuit(Database $db): void
    {
        $setter = \Closure::bind(
            function(string $prop, $val): void { if (property_exists($this, $prop)) { $this->{$prop} = $val; } },
            $db,
            Database::class
        );
        foreach (['cbFails'=>0,'cbOpenUntil'=>null] as $k=>$v) { $setter($k, $v); }
    }

    /*** TESTY ***/

    public function testInitPingDialectAndId(): void
    {
        $db = self::$db;
        $this->assertTrue(Database::isInitialized());
        $this->assertTrue($db->ping());
        $this->assertNotSame('', $db->id());
        $drv = $db->driver();
        $this->assertContains($drv, ['mysql','pgsql','sqlite']);
        // dialect()
        $dial = $db->dialect();
        $this->assertContains((string)$dial->name, ['mysql','postgres']);
    }

    public function testRequireSqlCommentEnforcedAndMetaWrappersBypass(): void
    {
        $db = self::$db;
        $db->requireSqlComment(true);

        try {
            // Trivial command passes without a comment (SELECT 1)
            $this->assertNotNull($db->fetchValue('SELECT 1', [], null));

            // Non-trivial SELECT without comment is rejected
            try {
                $db->fetchAll('SELECT * FROM items');
                $this->fail('Expected SQL comment guard to throw');
            } catch (DatabaseException $e) {
                $this->addToAssertionCount(1);
            }

            // wrapper adds app comment and passes
            $rows = $db->fetchAllWithMeta('SELECT * FROM items WHERE val >= :v', [':v'=>2], ['feature'=>'test']);
            $this->assertGreaterThanOrEqual(1, count($rows));
        } finally {
            $db->requireSqlComment(false);
        }
    }

    public function testDangerousSqlGuard(): void
    {
        $db = self::$db;
        $db->enableDangerousSqlGuard(true);

        try {
            // UPDATE bez WHERE = chyba (mimo MySQL s LIMIT)
            if ($db->isMysql()) {
                // bez WHERE i LIMIT – chyba
                $this->expectException(DatabaseException::class);
                $db->exec('UPDATE items SET val = 9');
            } else {
                // bez WHERE – chyba
                try {
                    $db->exec('UPDATE items SET val = 9');
                    $this->fail('Expected guard to throw');
                } catch (DatabaseException $e) {
                    $this->addToAssertionCount(1);
                }
            }

            if ($db->isMysql()) {
                // MySQL: LIMIT tolerated
                $db->exec('UPDATE items SET val = val+1 LIMIT 1');
                $this->assertTrue(true);
            }
        } finally {
            $db->enableDangerousSqlGuard(false);
        }
    }

    public function testPlaceholderGuardWarns(): void
    {
        $db = self::$db;
        self::$logger->lines = [];
        $db->enablePlaceholderGuard(true);
        // missing :x
        try { $db->fetchAll('SELECT :x AS y', []); } catch (\Throwable $e) { /* driver may complain; that's fine */ }
        $this->assertTrue(self::$logger->has(fn($l)=>$l['level']==='warning' && $l['msg'] === 'Placeholder mismatch'));
        $db->enablePlaceholderGuard(false);
    }

    public function testInsertManyAndUpsert(): void
    {
        $db = self::$db;

        $n = $db->insertMany('kv', [
            ['k'=>'a','v'=>1],
            ['k'=>'b','v'=>2],
        ]);
        $this->assertSame(2, $n);

        if ($db->driver() === 'sqlite') {
            $this->markTestSkipped('upsert() relies on PG/MySQL syntax - skip on SQLite.');
        }

        // upsert one row and a batch
        $db->upsert('kv', ['k'=>'a','v'=>11], ['k']);
        $db->upsert('kv', [
            ['k'=>'b','v'=>22],
            ['k'=>'c','v'=>33],
        ], ['k']);

        $pairs = $db->fetchPairs('SELECT k, v FROM kv ORDER BY k');
        $this->assertSame(['a'=>11,'b'=>22,'c'=>33], $pairs);
    }

    public function testPaginateKeyset(): void
    {
        $db = self::$db;

        // insert more rows
        $db->insertMany('items', [
            ['name'=>'d','val'=>4],
            ['name'=>'e','val'=>5],
            ['name'=>'f','val'=>6],
        ]);

        $base = 'SELECT id,name,val FROM items';
        $page1 = $db->paginateKeyset($base, [], 'id', 'id', null, 3, 'ASC');
        $this->assertCount(3, $page1['items']);
        $this->assertNotNull($page1['nextAfter']);

        $page2 = $db->paginateKeyset($base, [], 'id', 'id', $page1['nextAfter'], 3, 'ASC');
        $this->assertGreaterThanOrEqual(1, count($page2['items']));
    }

    public function testExistsVsExistsFast(): void
    {
        $db = self::$db;
        $this->assertTrue($db->exists('SELECT * FROM items WHERE name = :n', [':n'=>'a']));
        $this->assertFalse($db->exists('SELECT * FROM items WHERE name = :n', [':n'=>'zzz']));

        $this->assertTrue($db->existsFast('SELECT * FROM items WHERE name = :n', [':n'=>'a']));
        $this->assertFalse($db->existsFast('SELECT * FROM items WHERE name = :n', [':n'=>'zzz']));
    }

    public function testExplainJsonSmoke(): void
    {
        $db = self::$db;
        $plan = $db->explainJson('SELECT * FROM items WHERE name = :n', [':n'=>'a']);
        $this->assertIsArray($plan);
        $this->assertNotEmpty($plan);
    }

    public function testTxReadOnlyAndIsolationStrict(): void
    {
        $db = self::$db;

        // RO transakce
        $out = $db->transactionReadOnly(function(Database $d) {
            return $d->fetchValue('SELECT COUNT(*) FROM items', [], 0);
        });
        $this->assertGreaterThan(0, $out);

        // MySQL: withIsolationLevelStrict inside an active transaction must throw
        if ($db->isMysql()) {
            $this->expectException(DatabaseException::class);
            $db->transaction(function(Database $d) {
                $d->withIsolationLevelStrict('serializable', fn()=>null);
                return null;
            });
        } else {
            // PG/SQLite: allowed (SQLite falls back to transaction())
            $db->withIsolationLevel('read committed', fn()=>null);
            $this->assertTrue(true);
        }
    }

    public function testCircuitBreakerOpensAndBlocks(): void
    {
        $db = self::$db;
        self::$logger->lines = [];
        $db->configureCircuit(2, 60); // 2 chyby => open

        // trigger two errors (broken SQL)
        foreach ([1,2] as $_) {
            try { $db->fetchAll('SELECT * FROM __no_such_table__'); } catch (\Throwable $e) {}
        }
        // now the circuit should block even SELECT 1
        try {
            $db->fetchAll('SELECT 1');
            $this->fail('expected circuit open');
        } catch (DatabaseException $e) {
            $this->assertStringContainsString('circuit open', $e->getMessage());
        } finally {
            self::resetCircuit($db);
        }
    }

    public function testReplicaRoutingAndStickinessIfReplicaConfigured(): void
    {
        $db = self::$db;
        if (!$db->hasReplica()) {
            $this->markTestSkipped('Replica is not configured (BC_REPLICA_*).');
        }

        $db->setReplicaMaxLagMs(1000);
        $db->setReplicaHealthChecker(fn(\PDO $pdo) => 0);

        // read-only SELECT => replica
        usleep(($db->getStickAfterWriteMs()+50)*1000); // ensure stickiness window after seeding has passed
        self::$logger->lines = [];
        $db->fetchAll('SELECT * FROM items');
        $queries = $db->getLastQueries();
        $last = end($queries) ?: [];
        $this->assertSame('replica', $last['route']);

        // write => stickiness to primary
        $db->exec('INSERT INTO items (name,val) VALUES (:n,:v)', [':n'=>'sx',':v'=>99]);
        $db->fetchAll('SELECT * FROM items WHERE name = :n', [':n'=>'sx']);
        $queries = $db->getLastQueries();
        $last = end($queries) ?: [];
        $this->assertSame('primary', $last['route']);

        // after waiting fall back to replica
        usleep(($db->getStickAfterWriteMs()+50)*1000);
        $db->fetchAll('SELECT * FROM items WHERE name = :n', [':n'=>'a']);
        $queries = $db->getLastQueries();
        $last = end($queries) ?: [];
        $this->assertSame('replica', $last['route']);
    }

    public function testForceHintsAndSelectNeedingPrimary(): void
    {
        $db = self::$db;
        // FORCE:PRIMARY
        $db->fetchAll('/*FORCE:PRIMARY*/ SELECT * FROM items');
        $queries = $db->getLastQueries();
        $last = end($queries) ?: [];
        $this->assertSame('primary', $last['route']);

        if ($db->hasReplica()) {
            $db->setReplicaMaxLagMs(1000);
            $db->setReplicaHealthChecker(fn(\PDO $pdo)=>0);
            $db->fetchAll('/*FORCE:REPLICA*/ SELECT * FROM items WHERE name=:n', [':n'=>'a']);
            $queries = $db->getLastQueries();
            $last = end($queries) ?: [];
            $this->assertSame('replica', $last['route']);
        }

        if ($db->driver() !== 'sqlite') {
            // SELECT ... FOR UPDATE -> primary
            $db->fetchAll('SELECT * FROM items FOR UPDATE');
            $queries = $db->getLastQueries();
            $last = end($queries) ?: [];
            $this->assertSame('primary', $last['route']);
        }
    }

    public function testObserversReceiveCallbacks(): void
    {
        $db = self::$db;
        $obs = new TestObserver();
        $db->addObserver($obs);
        $db->fetchAll('SELECT 1');
        $this->assertNotEmpty($obs->events);
        $this->assertSame('start', $obs->events[0]['phase']);
        $this->assertSame('end',   $obs->events[1]['phase']);
    }

    public function testRingBufferTruncates(): void
    {
        $db = self::$db;
        $db->setLastQueriesMax(10);
        for ($i=0;$i<25;$i++) { try { $db->fetchAll('SELECT 1'); } catch (\Throwable $e) {} }
        $last = $db->getLastQueries();
        $this->assertLessThanOrEqual(10, count($last));
    }

    public function testFetchPairsExDuplicatePolicies(): void
    {
        $db = self::$db;
        $sql = 'SELECT 1 as k, 10 as v UNION ALL SELECT 1, 20';

        $last = $db->fetchPairsEx($sql, [], 'last');
        $this->assertSame([1=>20], $last);

        $first = $db->fetchPairsEx($sql, [], 'first');
        $this->assertSame([1=>10], $first);

        $this->expectException(DatabaseException::class);
        $db->fetchPairsEx($sql, [], 'error');
    }

    public function testIterators(): void
    {
        $db = self::$db;
        $vals = [];
        foreach ($db->iterate('SELECT name,val FROM items ORDER BY id ASC') as $r) {
            $vals[] = $r['name'];
        }
        $this->assertNotEmpty($vals);

        $col = iterator_to_array($db->iterateColumn('SELECT name FROM items ORDER BY id ASC'));
        $this->assertNotEmpty($col);
    }

    public function testWithEmulationToggles(): void
    {
        $db = self::$db;
        try {
            $inside = $db->withEmulation(true, function(Database $d) {
                return $d->getPdo()->getAttribute(\PDO::ATTR_EMULATE_PREPARES);
            });
            $this->assertTrue((bool)$inside);
        } catch (\Throwable $e) {
            $this->markTestSkipped('Driver nepodporuje ATTR_EMULATE_PREPARES toggling: '.$e->getMessage());
        }
    }

    public function testEncodeDecodeCursor(): void
    {
        $cur = ['id'=>123,'dir'=>'ASC'];
        $tok = Database::encodeCursor($cur);
        $dec = Database::decodeCursor($tok);
        $this->assertSame($cur, $dec);
        $this->assertNull(Database::decodeCursor('!!not_base64!!'));
    }

    public function testWithStatementTimeout(): void
    {
        $db = self::$db;
        $ok = $db->withStatementTimeout(50, function(Database $d) {
            return $d->fetchValue('SELECT 1', [], 0) == 1;
        });
        $this->assertTrue($ok);
    }

    public function testWithAdvisoryLock(): void
    {
        $db = self::$db;
        $ran = false;
        $db->withAdvisoryLock('bc:test:lock', 1, function() use (&$ran) { $ran = true; return null; });
        $this->assertTrue($ran);
    }

    public function testQuoteIdentProducesDriverStyle(): void
    {
        $db = self::$db;
        $q = $db->quoteIdent('t.col');
        if ($db->isMysql()) $this->assertStringContainsString('`t`.`col`', $q);
        else                $this->assertStringContainsString('"t"."col"', $q);
    }

    public function testWithPrimaryAndWithReplicaScopes(): void
    {
        $db = self::$db;
        if (!$db->hasReplica()) {
            $this->markTestSkipped('Replica is not configured.');
        }
        $db->setReplicaMaxLagMs(1000);
        $db->setReplicaHealthChecker(fn(\PDO $pdo)=>0);

        usleep(($db->getStickAfterWriteMs()+50)*1000);
        $db->withReplica(function(Database $d) {
            $d->fetchAll('SELECT * FROM items');
        });
        $queries = $db->getLastQueries();
        $last = end($queries) ?: [];
        $this->assertSame('replica', $last['route']);

        $db->withPrimary(function(Database $d) {
            $d->fetchAll('SELECT * FROM items');
        });
        $queries = $db->getLastQueries();
        $last = end($queries) ?: [];
        $this->assertSame('primary', $last['route']);
    }

    public function testNestedTransactionsCreateSavepoints(): void
    {
        $db = self::$db;
        $db->transaction(function(Database $d) {
            $d->transaction(function(Database $d2) {
                $d2->exec('INSERT INTO items (name,val) VALUES (:n,:v)', [':n'=>'nested',':v'=>99]);
            });
        });
        $this->assertTrue($db->exists('SELECT * FROM items WHERE name = :n', [':n'=>'nested']));
    }

    public function testLastInsertId(): void
    {
        $db = self::$db;
        $db->exec('INSERT INTO items (name,val) VALUES (:n,:v)', [':n'=>'liid',':v'=>10]);
        $id = $db->lastInsertId();
        $this->assertNotNull($id);
    }

    public function testReadOnlyGuardBlocksWrites(): void
    {
        $db = self::$db;
        $db->enableReadOnlyGuard(true);
        try {
            $this->expectException(DatabaseException::class);
            $db->exec('INSERT INTO items (name,val) VALUES ("ro", 1)');
        } finally {
            $db->enableReadOnlyGuard(false);
        }
    }

    public function testWaitForReplicaAndReplicaStatusStructure(): void
    {
        $db = self::$db;
        if (!$db->hasReplica()) {
            $this->markTestSkipped('Replica is not configured.');
        }
        $db->setReplicaMaxLagMs(1000);
        $db->setReplicaHealthChecker(fn(\PDO $pdo)=>0);
        usleep(($db->getStickAfterWriteMs()+50)*1000);
        $this->assertTrue($db->waitForReplica(300));
        $st = $db->replicaStatus();
        $this->assertArrayHasKey('hasReplica', $st);
        $this->assertArrayHasKey('lagMs', $st);
    }

    public function testInClauseBuilderWithChunking(): void
    {
        $db = self::$db;
        // create a larger set of IDs
        $db->insertMany('items', array_map(fn($i)=>['name'=>'z'.$i,'val'=>$i], range(10,60)));
        $ids = $db->fetchColumn('SELECT id FROM items ORDER BY id ASC');

        [$cond, $params] = $db->inClause($db->quoteIdent('id'), $ids, 'x', 20);
        $rows = $db->fetchAll('SELECT id FROM items WHERE '.$cond.' ORDER BY id ASC', $params);
        $this->assertCount(count($ids), $rows);
    }

    public function testOrderGuardEnvVar(): void
    {
        $db = self::$db;
        $old = getenv('BC_ORDER_GUARD') ?: '';
        putenv('BC_ORDER_GUARD=1');
        try {
            $this->expectException(DatabaseException::class);
            // triggers regex \bORDER\s+(?!BY\b)
            $db->fetchAll('SELECT * FROM items ORDER foo');
        } finally {
            putenv('BC_ORDER_GUARD='.$old);
        }
    }

    public function testWithStatementHelper(): void
    {
        $db = self::$db;
        $val = $db->withStatement('SELECT 1', function(\PDOStatement $st) {
            return $st->fetchColumn(0);
        });
        $this->assertEquals(1, (int)$val);
    }

    public function testCloseAndReinitViaReflection(): void
    {
        $db = self::$db;
        $db->close();
        // after close(), getPdo() cannot be used
        try {
            $db->fetchAll('SELECT 1');
            $this->fail('Expected DatabaseException after closing the connection');
        } catch (DatabaseException $e) {
            $this->addToAssertionCount(1);
        }
        // reset singletonu + re-init
        self::resetSingleton();
        self::setUpBeforeClass();
        $this->assertTrue(Database::getInstance()->ping());
    }

    /** Use the same DSN selection as bootstrap (mysql/pg), never fallback to sqlite. */
    private static function configFromEnv(): array
    {
        $raw = strtolower(trim((string)(getenv('BC_DB') ?: '')));
        $norm = match ($raw) {
            'mysql', 'mariadb' => 'mysql',
            'pg', 'pgsql', 'postgres', 'postgresql' => 'pg',
            default => '',
        };

        $myDsn  = getenv('MYSQL_DSN')  ?: (getenv('MARIADB_DSN') ?: '');
        $myUser = getenv('MYSQL_USER') ?: (getenv('MARIADB_USER') ?: 'root');
        $myPass = getenv('MYSQL_PASS') ?: (getenv('MARIADB_PASS') ?: 'root');
        $pgDsn  = getenv('PG_DSN')  ?: '';
        $pgUser = getenv('PG_USER') ?: 'postgres';
        $pgPass = getenv('PG_PASS') ?: 'postgres';

        if ($norm === '') {
            if ($myDsn && !$pgDsn) {
                $norm = 'mysql';
            } elseif ($pgDsn && !$myDsn) {
                $norm = 'pg';
            } else {
                $norm = 'mysql'; // match phpunit defaults
            }
            @putenv("BC_DB={$norm}");
        }

        $replica = null;
        if (getenv('BC_REPLICA_DSN')) {
            $replica = [
                'dsn' => getenv('BC_REPLICA_DSN'),
                'user'=> getenv('BC_REPLICA_USER') ?: null,
                'pass'=> getenv('BC_REPLICA_PASS') ?: null,
                'options' => [],
                'init_commands' => []
            ];
        }

        if ($norm === 'pg') {
            $dsn  = $pgDsn ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
            $user = $pgUser;
            $pass = $pgPass;
            $init = [
                "SET TIME ZONE 'UTC'",
                "SET client_encoding TO 'UTF8'",
            ];
        } else {
            $dsn  = $myDsn ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';
            $user = $myUser;
            $pass = $myPass;
            $init = ["SET time_zone = '+00:00'"];
        }

        return [
            'dsn' => $dsn,
            'user'=> $user,
            'pass'=> $pass,
            'options' => [],
            'init_commands' => $init,
            'appName' => 'blackcat-tests',
            'replica' => $replica,
            'replicaStickMs' => 200,
            'statementTimeoutMs' => 2000,
            'lockWaitTimeoutSec' => 1,
        ];
    }
}
