<?php
declare(strict_types=1);

use BlackCat\Core\Database;
use BlackCat\Database\Installer;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Contracts\ModuleInterface;

require __DIR__ . '/bootstrap.php';

/* ---------- DB bootstrap ---------- */
$which = getenv('BC_DB') ?: 'mysql';
if ($which === 'mysql') {
    $dsn  = getenv('MYSQL_DSN')  ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';
    $user = getenv('MYSQL_USER') ?: 'root';
    $pass = getenv('MYSQL_PASS') ?: 'root';
} else {
    $dsn  = getenv('PG_DSN')  ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
    $user = getenv('PG_USER') ?: 'postgres';
    $pass = getenv('PG_PASS') ?: 'postgres';
}

Database::init([
    'dsn' => $dsn,
    'user'=> $user,
    'pass'=> $pass,
    'init_commands' => [
        // bezpečné defaulty (pokud driver dovolí)
        "SET timezone TO 'UTC'"
    ]
]);

$db      = Database::getInstance();
$driver  = $db->getPdo()->getAttribute(PDO::ATTR_DRIVER_NAME);
$dialect = $driver === 'mysql' ? SqlDialect::mysql : SqlDialect::postgres;
// ↓↓↓ HOTFIX: minimalizace RAM při dotazech
$pdo = $db->getPdo();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
$pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false); // lepší paměťové chování u větších bindů
if ($driver === 'mysql') {
    // Ne-bufferovat výsledky (jinak je driver tahá celé do RAM)
    if (defined('PDO::MYSQL_ATTR_USE_BUFFERED_QUERY')) {
        $pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false);
    }
}
$runIdempotent = (getenv('BC_RUN_IDEMPOTENT') ?: '0') === '1';
$runUninstall  = (getenv('BC_UNINSTALL') ?: '0') === '1';
/* ---------- BC_REPAIR volitelnost (TTY=ON, CI=OFF, lze přepnout) ---------- */
// PRIORITA: explicitní env > CLI přepínač > autodetekce TTY (mimo CI)
$argvList      = $_SERVER['argv'] ?? [];
$cliRepairOn   = in_array('--repair', $argvList, true) || in_array('-r', $argvList, true);
$cliRepairOff  = in_array('--no-repair', $argvList, true);
$envRepair     = getenv('BC_REPAIR'); // '1' | '0' | false (není nastaveno)
$isCI          = (getenv('CI') === 'true') || (getenv('GITHUB_ACTIONS') === 'true');

// detekce TTY bez závislosti na posix
$isTty = false;
if (function_exists('stream_isatty')) {
    $isTty = @stream_isatty(STDOUT);
} elseif (function_exists('posix_isatty')) {
    $isTty = @posix_isatty(STDOUT);
}

// Rozhodnutí
$effective = null; // '1' nebo '0'
if ($envRepair !== false && $envRepair !== '') {
    $effective = ((string)$envRepair === '1' || strtolower((string)$envRepair) === 'true') ? '1' : '0';
} elseif ($cliRepairOn || $cliRepairOff) {
    $effective = $cliRepairOn ? '1' : '0';
} else {
    // Autodetekce: pokud běžíme interaktivně (TTY) a nejsme v CI → zapni repair
    $effective = ($isTty && !$isCI) ? '1' : '0';
}

// Propagace do prostředí
putenv('BC_REPAIR=' . $effective);
$_ENV['BC_REPAIR'] = $effective;

// Volitelné „tiché“ info jen v interaktivním režimu
if ($isTty) {
    fwrite(STDERR, "[info] BC_REPAIR={$effective}" . PHP_EOL);
}

/* ---------- Najdi všechny module classes ---------- */
$modules = []; // [FQN => ['pkg'=>string, 'deps'=>string[], 'obj'=>ModuleInterface]]

$pattern = realpath(__DIR__ . '/../../packages');
if ($pattern === false) { fwrite(STDERR, "packages/ not found.\n"); exit(2); }

$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($pattern, FilesystemIterator::SKIP_DOTS));
foreach ($it as $f) {
    if ($f->isFile() && preg_match('~/packages/([^/]+)/src/([A-Za-z0-9_]+)Module\.php$~', $f->getPathname(), $m)) {
        $pkgDir = $m[1]; // např. "email-verifications" nebo "book_categories"
        // kebab/snake -> PascalCase
        $pkgPascal = implode('', array_map(
            fn($x) => ucfirst($x),
            preg_split('/[_-]/', $pkgDir)
        ));
        $class = "BlackCat\\Database\\Packages\\{$pkgPascal}\\{$pkgPascal}Module";
        if (!class_exists($class)) {
            // trigger autoload (file already exist -> autoload should hit it)
            require_once $f->getPathname();
        }
        if (!class_exists($class)) {
            fwrite(STDERR, "Module class not found/loaded: $class (from $pkgDir)\n");
            exit(3);
        }
        /** @var ModuleInterface $obj */
        $obj = new $class();
        // skip pokud modul nepodporuje daný dialect
        if (!in_array($dialect->value, $obj->dialects(), true)) continue;
        $modules[$class] = [
            'pkg'        => $pkgDir,      // např. "email-verifications"
            'pkg_pascal' => $pkgPascal,   // např. "EmailVerifications"
            'deps'       => $obj->dependencies(),
            'obj'        => $obj
        ];
    }
}
if (!$modules) { fwrite(STDERR, "No modules discovered.\n"); exit(4); }

/* ---------- Topologické řazení podle dependencies ---------- */
$graph = [];
$inDeg = [];
foreach ($modules as $fqn => $meta) {
    $graph[$fqn] = [];
    $inDeg[$fqn] = 0;
}
foreach ($modules as $fqn => $meta) {
    foreach ($meta['deps'] as $depName) {
        // očekáváme formát 'table-<snake>' => převeď na FQN
        if (str_starts_with($depName, 'table-')) {
            $snake = substr($depName, 6);
            $pkgPascal = implode('', array_map(fn($x)=>ucfirst($x), preg_split('/[_-]/', $snake)));
            $depFqn = "BlackCat\\Database\\Packages\\{$pkgPascal}\\{$pkgPascal}Module";
            if (isset($modules[$depFqn])) {
                $graph[$depFqn][] = $fqn;
                $inDeg[$fqn]++;
            }
        }
    }
}
// Kahn
$queue = [];
foreach ($inDeg as $k=>$deg) if ($deg===0) $queue[]=$k;
$order = [];
while ($queue) {
    $n = array_shift($queue);
    $order[] = $n;
    foreach ($graph[$n] as $m) { $inDeg[$m]--; if ($inDeg[$m]===0) $queue[]=$m; }
}
if (count($order) !== count($modules)) {
    fwrite(STDERR, "Dependency cycle detected among modules.\n");
    exit(5);
}

/* ---------- Install / Status assertions ---------- */
$installer = new Installer($db, $dialect);
$installer->ensureRegistry();

$fail = 0;
$reports = [];

foreach ($order as $fqn) {
    /** @var ModuleInterface $m */
    $m = $modules[$fqn]['obj'];
    $name = $m->name();

    // install or upgrade
    try {
        $installer->installOrUpgrade($m);
    } catch (Throwable $e) {
        fwrite(STDERR, "[FAIL][install] {$modules[$fqn]['pkg']}: " . $e->getMessage() . "\n");
        $fail++; continue;
    }

    // Idempotentní druhý běh (pokud zapnuto)
    if ($runIdempotent) {
        try {
            $installer->installOrUpgrade($m);
        } catch (Throwable $e) {
            fwrite(STDERR, "[FAIL][idempotent] {$modules[$fqn]['pkg']}: " . $e->getMessage() . "\n");
            $fail++; continue;
        }
    }

    // status
    try {
        $st = $m->status($db, $dialect);
        $okTable = !empty($st['table']);
        $okView  = !empty($st['view']);
        $okIdx   = empty($st['missing_idx'] ?? []);
        $okFk    = empty($st['missing_fk'] ?? []);
        $verOk   = ($st['version'] ?? '') === $m->version();

        if (!$okTable || !$okView || !$okIdx || !$okFk || !$verOk) {
            $fail++;
            fwrite(STDERR, "[FAIL][status] $name ".
                json_encode(['table'=>$okTable,'view'=>$okView,'idx'=>$okIdx,'fk'=>$okFk,'ver'=>$verOk, 'raw'=>$st], JSON_UNESCAPED_SLASHES) . "\n");
        } else {
            $reports[] = "[OK] $name v" . $m->version();
        }
    } catch (Throwable $e) {
        fwrite(STDERR, "[FAIL][status] {$modules[$fqn]['pkg']}: " . $e->getMessage() . "\n");
        $fail++; continue;
    }
}
/* ---------- Uninstall smoke test (jen view) ---------- */
if ($runUninstall) {
    foreach ($order as $fqn) {
        /** @var ModuleInterface $m */
        $m = $modules[$fqn]['obj'];
        try {
            $m->uninstall($db, $dialect);
            // po uninstall by měl být view pryč, tabulka zůstává
            $st = $m->status($db, $dialect);
            $okViewGone = empty($st['view']);
            $okTableStay= !empty($st['table']);
            if (!$okViewGone || !$okTableStay) {
                $fail++;
                fwrite(STDERR, "[FAIL][uninstall] {$m->name()} ".
                    json_encode(['view_gone'=>$okViewGone,'table_present'=>$okTableStay,'raw'=>$st], JSON_UNESCAPED_SLASHES)."\n");
            }
            // reinstall abychom neovlivnili další joby
            $installer->installOrUpgrade($m);
        } catch (Throwable $e) {
            fwrite(STDERR, "[FAIL][uninstall] {$modules[$fqn]['pkg']}: " . $e->getMessage() . "\n");
            $fail++; continue;
        }
    }
}
/* ---------- Summary ---------- */
foreach ($reports as $line) { echo $line, "\n"; }
if ($fail > 0) {
    echo "FAILED modules: $fail\n";
    exit(10);
}
echo "ALL GREEN (", count($reports), " modules)\n";
