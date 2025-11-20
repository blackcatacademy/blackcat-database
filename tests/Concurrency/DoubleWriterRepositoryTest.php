<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Concurrency;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;
use BlackCat\Database\Tests\Support\ConnFactory;

/**
 * Two repository layers (in two processes):
 *  - Locker:  tests/support/lock_row_repo.php  -> Repository::lockById()
 *  - Writer:  tento test -> Repository::updateById()
 *
 * Verifies:
 *  1) lock timeout during write
 *  2) update succeeds after the lock is released
 *  3) (when table has version) - optimistic locking repo-vs-repo with a stale version
 */
final class DoubleWriterRepositoryTest extends TestCase
{
    private static ?string $repoFqn = null;
    private static ?string $table   = null;
    private static ?string $updCol  = null;
    private static ?string $verCol  = null;

    public static function setUpBeforeClass(): void
    {
        DbHarness::ensureInstalled();
        if (self::isDebug()) {
            $db = Database::getInstance();
            $db->enableDebug(true);
            // optional - log slow queries immediately:
            $db->setSlowQueryThresholdMs(0);
        }
        // Find the first package via Definitions and derive the repo (via DbHarness::repoFor)
        foreach (glob(__DIR__ . '/../../packages/*/src/Definitions.php') as $df) {
            require_once $df;
            if (!preg_match('~[\\\\/]packages[\\\\/]([A-Za-z0-9_]+)[\\\\/]src[\\\\/]Definitions\.php$~i', $df, $m)) {
                continue;
            }
            $pkgPascal = $m[1];
            self::dbg('Considering package %s', $pkgPascal);
            $defs = "BlackCat\\Database\\Packages\\{$pkgPascal}\\Definitions";
            if (!class_exists($defs)) { self::dbg('Skip %s: no Definitions class (%s)', $pkgPascal, $defs); continue; }

            // ---- stricter filters ----
            if (!$defs::isIdentityPk()) {
                self::dbg('Skip %s: not identity PK', $pkgPascal);
                continue;
            }
            if (!$defs::isRowLockSafe()) {
                self::dbg('Skip %s: not row-lock-safe', $pkgPascal);
                continue;
            }
            if (!$defs::supportsOptimisticLocking()) {
                self::dbg('Skip %s: no optimistic locking (no version column)', $pkgPascal);
                continue;
            }

            $table  = $defs::table();
            $verCol = $defs::versionColumn(); // guaranteed non-null

            // choose an updatable column from Definitions::columns (!= id, != version, != audit/soft-delete)
            $bad    = ['id', (string)$verCol, 'created_at', 'updated_at', 'deleted_at'];
            $updCol = null;
            foreach ((array)$defs::columns() as $name) {
                $name = (string)$name;
                if ($name === '' || in_array($name, $bad, true)) continue;
                $updCol = $name; break;
            }
            if (!$updCol) {
                self::dbg('Skip %s: no suitable updatable column', $pkgPascal);
                continue;
            }
            // Pre-flight: ensure RowFactory can build a sample for this table.
            // Otherwise skip the package to avoid later insert failures.
            [$sample] = RowFactory::makeSample($table);
            if ($sample === null) {
                self::dbg('Skip %s: RowFactory cannot build safe sample for table=%s', $pkgPascal, $table);
                continue;
            }
            // ensure the chosen column is allowed by the Repository (whitelist)
            $allowed = DbHarness::allowedColumns($table);
            if (!in_array($updCol, $allowed, true)) {
                self::dbg('Skip %s: chosen updCol=%s not allowed by repo (table=%s)', $pkgPascal, $updCol, $table);
                continue;
            }
            // obtain the actual repository FQN via DbHarness
            $repoObj = DbHarness::repoFor($table);
            $repoFqn = get_class($repoObj);
            self::dbg('Selected repo=%s table=%s updCol=%s verCol=%s', $repoFqn, $table, $updCol, (string)$verCol);

            self::$repoFqn = $repoFqn;
            self::$table   = $table;
            self::$updCol  = $updCol;
            self::$verCol  = $verCol;
            break;
        }

        if (!self::$repoFqn) {
            self::markTestSkipped('No suitable Repository with identity PK found.');
        }
    }

    private static function isDebug(): bool
    {
        $val = $_ENV['BC_DEBUG'] ?? getenv('BC_DEBUG') ?? '';
        return $val === '1' || strcasecmp((string)$val, 'true') === 0;
    }

    private static function dbg(string $fmt, mixed ...$args): void
    {
        if (!self::isDebug()) return;
        error_log('[DoubleWriterRepositoryTest] ' . vsprintf($fmt, $args));
    }

    private function insertRowAndGetId(): int
    {
        try {
            $ins = RowFactory::insertSample(self::$table);
        } catch (\Throwable $e) {
            self::markTestSkipped(
                'RowFactory cannot construct safe sample for table ' . self::$table . ': ' . $e->getMessage()
            );
            return 0; // unreachable, keeps the signature happy
        }
        self::dbg('Inserted sample into %s: %s=%s', self::$table, $ins['pkCol'], (string)$ins['pk']);
        return (int)$ins['pk'];
    }

    public function test_repo_update_times_out_while_other_repo_holds_lock(): void
    {
        $db  = Database::getInstance();
        $pdo = $db->getPdo();

        $id = $this->insertRowAndGetId();
        self::dbg('Inserted id=%d (lock-timeout test)', $id);
        $this->assertGreaterThan(0, $id);

        // Run the locker process (Repository::lockById) for N seconds
        $repoFqn  = self::$repoFqn;
        $seconds  = 5; // hold lock for ~5s
        self::dbg('Starting locker for %d s via %s', $seconds, $repoFqn);
        $cmd = sprintf(
            'php %s "%s" %d %d',
            escapeshellarg(__DIR__.'/../support/lock_row_repo.php'),
            $repoFqn,
            $id,
            $seconds
        );
        $desc = [['pipe','r'],['pipe','w'],['pipe','w']];

        // Pass DB env variables (and a few basics) to the child process
        $forward = ['BC_DB','MYSQL_DSN','MYSQL_USER','MYSQL_PASS','MARIADB_DSN','MARIADB_USER','MARIADB_PASS','PG_DSN','PG_USER','PG_PASS','BC_PG_SCHEMA','BC_DEBUG','PATH','HOME'];
        $env = [];
        foreach ($forward as $k) {
            $v = getenv($k);
            if ($v !== false) { $env[$k] = $v; }
        }

        $proc = proc_open($cmd, $desc, $pipes, __DIR__.'/../../', $env);
        $this->assertIsResource($proc, 'Failed to start locker process');
        // --- READ LOCKER OUTPUT (stdout/stderr) ---
        foreach ($pipes as $p) { if (is_resource($p)) stream_set_blocking($p, false); }
        $readLocker = function() use ($pipes) {
            $out = is_resource($pipes[1]) ? stream_get_contents($pipes[1]) : '';
            $err = is_resource($pipes[2]) ? stream_get_contents($pipes[2]) : '';
            if ($out !== '') self::dbg('[locker-stdout] %s', trim($out));
            if ($err !== '') self::dbg('[locker-stderr] %s', trim($err));
        };
        $readLocker();
        // Give the locker process time to acquire the FOR UPDATE lock
        usleep(600_000); // 300ms

        // writer - reduce lock timeout and attempt an update via Repository
        ConnFactory::setShortLockTimeout($pdo, 1000);
        self::dbg('Attempting write under lock (should timeout)…');
        $repo = new $repoFqn($db);
        self::dbg('repo class real = %s', get_class($repo));
        $thrown = null;
        try {
            // without optimistic param - plain write that should block
            $repo->updateById($id, [ self::$updCol => 'x-lock' ]);
            $this->fail('Expected lock wait timeout, but update succeeded.');
        } catch (\Throwable $e) {
            $thrown = $e;
        }
        $this->assertNotNull($thrown, 'Lock wait timeout was not thrown.');

        // Wait for the locker process to finish (release lock)
        $status = proc_get_status($proc);
        while ($status && $status['running']) {
            usleep(100_000);
            $readLocker();
            $status = proc_get_status($proc);
        }
        $readLocker();
        foreach ($pipes as $p) { if (is_resource($p)) fclose($p); }
        if (is_resource($proc)) proc_close($proc);

        // Now the update should succeed
        self::dbg('Trying write after lock released…');
        $aff = $repo->updateById($id, [ self::$updCol => 'x-after' ]);
        self::dbg('aff(after)=%d', $aff);
        $this->assertSame(1, $aff, 'Update should succeed after lock released.');
    }

    public function test_repo_vs_repo_optimistic_locking_with_stale_version_if_supported(): void
    {
        if (!self::$verCol) {
            $this->markTestSkipped('Selected table has no version column.');
        }

        $db  = Database::getInstance();
        $pdo = $db->getPdo();

        $id = $this->insertRowAndGetId();
        $this->assertGreaterThan(0, $id);
        $pkCol = DbHarness::primaryKey(self::$table);
        $ver = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE {$pkCol}=:id", [':id'=>$id]);
        self::dbg('Inserted id=%d (optimistic test), initial version=%d', $id, $ver);

        // Locker process holds the lock via Repository::lockById
        $repoFqn = self::$repoFqn;
        $cmd = sprintf(
            'php %s "%s" %d %d',
            escapeshellarg(__DIR__.'/../support/lock_row_repo.php'),
            $repoFqn,
            $id,
            3
        );
        $forward = ['BC_DB','MYSQL_DSN','MYSQL_USER','MYSQL_PASS','MARIADB_DSN','MARIADB_USER','MARIADB_PASS','PG_DSN','PG_USER','PG_PASS','BC_PG_SCHEMA','BC_DEBUG','PATH','HOME'];
        $env = [];
        foreach ($forward as $k) {
            $v = getenv($k);
            if ($v !== false) { $env[$k] = $v; }
        }

        $proc = proc_open($cmd, [['pipe','r'],['pipe','w'],['pipe','w']], $pipes, __DIR__.'/../../', $env);
        $this->assertIsResource($proc, 'Failed to start locker process');
        // --- READ LOCKER OUTPUT (stdout/stderr) ---
        foreach ($pipes as $p) { if (is_resource($p)) stream_set_blocking($p, false); }
        $readLocker = function() use ($pipes) {
            $out = is_resource($pipes[1]) ? stream_get_contents($pipes[1]) : '';
            $err = is_resource($pipes[2]) ? stream_get_contents($pipes[2]) : '';
            if ($out !== '') self::dbg('[locker-stdout] %s', trim($out));
            if ($err !== '') self::dbg('[locker-stderr] %s', trim($err));
        };

        usleep(600_000); // 300ms to acquire the lock
        $readLocker();
        // Writer shortens lock timeout and attempts an update with expected version -> timeout (before release)
        ConnFactory::setShortLockTimeout($pdo, 1000);
        $repo = new $repoFqn($db);
        self::dbg('repo class real = %s', get_class($repo));
        $caught = null;
        try {
            $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r1' ]);
            $this->fail('Expected lock wait timeout before lock release.');
        } catch (\Throwable $e) { $caught = $e; }
        $this->assertNotNull($caught);
        // <- HERE: version is still locked (locker still running)
        $verDuringLock = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE {$pkCol}=:id", [':id'=>$id]);
        self::dbg('Version immediately after timeout (still locked)=%d', $verDuringLock);

        // For safety log the current lock wait timeout for this connection
        try {
            if (method_exists($db, 'isMysql') && $db->isMysql()) {
                $lockWait = (int)$db->fetchOne('SELECT @@innodb_lock_wait_timeout', []);
                self::dbg('@@innodb_lock_wait_timeout=%d', $lockWait);
            } else {
                // Postgres: SHOW lock_timeout returns strings like "1s"
                $pgTimeout = (string)$db->fetchOne('SHOW lock_timeout', []);
                self::dbg('lock_timeout=%s', $pgTimeout);
            }
        } catch (\Throwable $e) {
            self::dbg('Could not query lock timeout: %s', $e->getMessage());
        }

        // After releasing the lock the first update succeeds -> version++
        $status = proc_get_status($proc);
        while ($status && $status['running']) {
            usleep(100_000);
            $readLocker();                 // <- added: poll locker stdout/stderr
            $status = proc_get_status($proc);
        } 
        $readLocker();
        foreach ($pipes as $p) { if (is_resource($p)) fclose($p); }
        if (is_resource($proc)) proc_close($proc);
        $verBefore = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE {$pkCol}=:id", [':id'=>$id]);
        self::dbg('Version right before optimistic update=%d (expected=%d)', $verBefore, $ver);
        $aff1 = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r2' ]);
        $verAfter = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE {$pkCol}=:id", [':id'=>$id]);
        self::dbg('Version after optimistic attempt=%d', $verAfter);
        $this->assertSame(1, $aff1, 'First optimistic update should succeed.');

        // Second writer (stale version) - simulate by reusing 'ver' (unchanged)
        self::dbg('Second optimistic update with stale version=%d (should be 0)', $ver);
        $aff2 = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r3' ]);
        self::dbg('aff2=%d', $aff2);
        $this->assertSame(0, $aff2, 'Second optimistic update with stale version must affect 0 rows.');
    }
}
