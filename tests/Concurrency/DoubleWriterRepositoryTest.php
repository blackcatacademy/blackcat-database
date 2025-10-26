<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Concurrency;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Tests\Support\DbHarness;
use BlackCat\Database\Tests\Support\RowFactory;
use BlackCat\Database\Tests\Support\ConnFactory;

/**
 * Dvě repo vrstvy (ve dvou procesech):
 *  - Locker:  tests/support/lock_row_repo.php  -> Repository::lockById()
 *  - Writer:  tento test -> Repository::updateById()
 *
 * Ověřuje:
 *  1) lock timeout během zápisu
 *  2) po uvolnění zámku update projde
 *  3) (pokud má tabulka version) – optimistic locking repo-vs-repo se stale verzí
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
            // volitelné – loguj i pomalé dotazy hned:
            $db->setSlowQueryThresholdMs(0);
        }
        // Najdi první balík, který má Repository a tabulku s PK=id a updatovatelným sloupcem
        foreach (glob(__DIR__ . '/../../packages/*/src/Definitions.php') as $df) {
            require_once $df;
            if (!preg_match('~[\\\\/]packages[\\\\/]([A-Za-z0-9_]+)[\\\\/]src[\\\\/]Definitions\.php$~i', $df, $m)) {
                continue;
            }
            $pkgPascal = $m[1];
            self::dbg('Considering package %s', $pkgPascal);
            $defs = "BlackCat\\Database\\Packages\\{$pkgPascal}\\Definitions";
            $repo = "BlackCat\\Database\\Packages\\{$pkgPascal}\\Repository";
            if (!class_exists($defs) || !class_exists($repo)) {
                self::dbg('Skip %s: no classes (defs=%s, repo=%s)', $pkgPascal, $defs, $repo);
                continue;
            }

            // ---- přísnější filtry ----
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

            $table   = $defs::table();
            $verCol  = $defs::versionColumn(); // už víme, že není null
            $columns = DbHarness::columns($table);

            // vyber rozumný updatovatelný sloupec (≠ id, ≠ version, ≠ audit/soft-delete)
            $bad = ['id', (string)$verCol, 'created_at', 'updated_at', 'deleted_at'];
            $updCol = null;
            foreach ($columns as $c) {
                $name = $c['name'] ?? null;
                if (!$name) continue;
                if (in_array($name, $bad, true)) continue;
                $updCol = $name;
                break;
            }
            if (!$updCol) {
                self::dbg('Skip %s: no suitable updatable column', $pkgPascal);
                continue;
            }
            self::dbg('Selected repo=%s table=%s updCol=%s verCol=%s', $repo, $table, $updCol, (string)$verCol);

            self::$repoFqn = $repo;
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

    private function insertRowAndGetId(Database $db): int
    {
        [$row] = RowFactory::makeSample(self::$table);
        $cols = array_keys($row);
        $ph   = array_map(fn($c)=>":$c", $cols);
        $db->execute(
            "INSERT INTO ".self::$table." (".implode(',', $cols).") VALUES (".implode(',', $ph).")",
            array_combine($ph, array_values($row))
        );
        return (int)$db->fetchOne("SELECT id FROM ".self::$table." ORDER BY id DESC LIMIT 1");
    }

    public function test_repo_update_times_out_while_other_repo_holds_lock(): void
    {
        $db  = Database::getInstance();
        $pdo = $db->getPdo();

        $id = $this->insertRowAndGetId($db);
        self::dbg('Inserted id=%d (lock-timeout test)', $id);
        $this->assertGreaterThan(0, $id);

        // Spusť locker proces (Repository::lockById) na N sekund
        $repoFqn  = self::$repoFqn;
        $seconds  = 5; // držet lock ~5s
        self::dbg('Starting locker for %d s via %s', $seconds, $repoFqn);
        $cmd = sprintf(
            'php %s "%s" %d %d',
            escapeshellarg(__DIR__.'/../support/lock_row_repo.php'),
            $repoFqn,
            $id,
            $seconds
        );
        $desc = [['pipe','r'],['pipe','w'],['pipe','w']];

        // Předej do child procesu DB env proměnné (a pár základních)
        $forward = ['BC_DB','MYSQL_DSN','MYSQL_USER','MYSQL_PASS','PG_DSN','PG_USER','PG_PASS','BC_DEBUG','PATH','HOME'];
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
        // Dej locker procesu čas nabrat FOR UPDATE lock
        usleep(300_000); // 300ms

        // writer – zkrať lock timeout a pokus se o update přes Repository
        ConnFactory::setShortLockTimeout($pdo, 1000);
        self::dbg('Attempting write under lock (should timeout)…');
        $repo = new $repoFqn($db);
        self::dbg('repo class real = %s', get_class($repo));
        $thrown = null;
        try {
            // bez optimistic param – čistý zápis, který se má blokovat
            $repo->updateById($id, [ self::$updCol => 'x-lock' ]);
            $this->fail('Expected lock wait timeout, but update succeeded.');
        } catch (\Throwable $e) {
            $thrown = $e;
        }
        $this->assertNotNull($thrown, 'Lock wait timeout was not thrown.');

        // Počkej až locker proces skončí (uvolní lock)
        $status = proc_get_status($proc);
        while ($status && $status['running']) {
            usleep(100_000);
            $readLocker();
            $status = proc_get_status($proc);
        }
        $readLocker();
        foreach ($pipes as $p) { if (is_resource($p)) fclose($p); }
        if (is_resource($proc)) proc_close($proc);

        // Teď už update projde
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

        $id = $this->insertRowAndGetId($db);
        $this->assertGreaterThan(0, $id);
        $ver = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE id=:id", [':id'=>$id]);
        self::dbg('Inserted id=%d (optimistic test), initial version=%d', $id, $ver);

        // Locker proces drží lock přes Repository::lockById
        $repoFqn = self::$repoFqn;
        $cmd = sprintf(
            'php %s "%s" %d %d',
            escapeshellarg(__DIR__.'/../support/lock_row_repo.php'),
            $repoFqn,
            $id,
            3
        );
        $forward = ['BC_DB','MYSQL_DSN','MYSQL_USER','MYSQL_PASS','PG_DSN','PG_USER','PG_PASS','BC_DEBUG','PATH','HOME'];
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

        usleep(300_000); // 300ms na získání zámku
        $readLocker();
        // Writer zkrátí lock timeout a pokusí se o update s očekávanou verzí -> timeout (před uvolněním)
        ConnFactory::setShortLockTimeout($pdo, 1000);
        $repo = new $repoFqn($db);
        self::dbg('repo class real = %s', get_class($repo));
        $caught = null;
        try {
            $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r1' ]);
            $this->fail('Expected lock wait timeout before lock release.');
        } catch (\Throwable $e) { $caught = $e; }
        $this->assertNotNull($caught);
        // <- TADY: verze je stále pod zámkem (locker ještě běží)
        $verDuringLock = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE id=:id", [':id'=>$id]);
        self::dbg('Version immediately after timeout (still locked)=%d', $verDuringLock);

        // Pro jistotu si zaloguj aktuální lock wait timeout v tomhle connection
        $lockWait = (int)$db->fetchOne('SELECT @@innodb_lock_wait_timeout', []);
        self::dbg('@@innodb_lock_wait_timeout=%d', $lockWait);

        // Po uvolnění zámku proběhne první update -> verze ++
        $status = proc_get_status($proc);
        while ($status && $status['running']) {
            usleep(100_000);
            $readLocker();                 // ← přidáno: průběžně sbírej stdout/stderr lockera
            $status = proc_get_status($proc);
        } 
        $readLocker();
        foreach ($pipes as $p) { if (is_resource($p)) fclose($p); }
        if (is_resource($proc)) proc_close($proc);
        $verBefore = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE id=:id", [':id'=>$id]);
        self::dbg('Version right before optimistic update=%d (expected=%d)', $verBefore, $ver);
        $aff1 = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r2' ]);
        $verAfter = (int)$db->fetchOne("SELECT ".self::$verCol." FROM ".self::$table." WHERE id=:id", [':id'=>$id]);
        self::dbg('Version after optimistic attempt=%d', $verAfter);
        $this->assertSame(1, $aff1, 'First optimistic update should succeed.');

        // Druhý writer (stale version) – simuluj tak, že použijeme opět 'ver' (nezvýšený)
        self::dbg('Second optimistic update with stale version=%d (should be 0)', $ver);
        $aff2 = $repo->updateById($id, [ self::$verCol => $ver, self::$updCol => 'r3' ]);
        self::dbg('aff2=%d', $aff2);
        $this->assertSame(0, $aff2, 'Second optimistic update with stale version must affect 0 rows.');
    }
}
