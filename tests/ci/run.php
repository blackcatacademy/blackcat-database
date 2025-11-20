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
        // safe defaults when the driver permits
        "SET timezone TO 'UTC'"
    ]
]);

$db      = Database::getInstance();
$driver  = $db->getPdo()->getAttribute(PDO::ATTR_DRIVER_NAME);
$dialect = $driver === 'mysql' ? SqlDialect::mysql : SqlDialect::postgres;
// ↓↓↓ HOTFIX: minimize RAM usage during queries
$pdo = $db->getPdo();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
$pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false); // better memory handling for larger binds
if ($driver === 'mysql') {
    // Do not buffer results (otherwise the driver loads everything into RAM)
    if (defined('PDO::MYSQL_ATTR_USE_BUFFERED_QUERY')) {
        $pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false);
    }
}
$runIdempotent = (getenv('BC_RUN_IDEMPOTENT') ?: '0') === '1';
$runUninstall  = (getenv('BC_UNINSTALL') ?: '0') === '1';
$featureViewsEnv = getenv('BC_INCLUDE_FEATURE_VIEWS');
if ($featureViewsEnv === false || $featureViewsEnv === '') {
    // Enable feature views by default in tests unless explicitly disabled
    putenv('BC_INCLUDE_FEATURE_VIEWS=1');
    $_ENV['BC_INCLUDE_FEATURE_VIEWS'] = '1';
}
/* ---------- BC_REPAIR optional (TTY=ON, CI=OFF, overrideable) ---------- */
// PRIORITY: explicit env > CLI switch > TTY autodetect (outside CI)
$argvList      = $_SERVER['argv'] ?? [];
$moduleFiltersRaw = [];
for ($i = 1, $len = count($argvList); $i < $len; $i++) {
    $arg = $argvList[$i];
    if ($arg === '--module' || $arg === '-m') {
        if (!isset($argvList[$i + 1])) {
            fwrite(STDERR, "--module requires a value\n");
            exit(9);
        }
        $moduleFiltersRaw[] = $argvList[++$i];
        continue;
    }
    if ($arg === '--modules') {
        if (!isset($argvList[$i + 1])) {
            fwrite(STDERR, "--modules requires a value\n");
            exit(9);
        }
        $moduleFiltersRaw[] = $argvList[++$i];
        continue;
    }
    if (str_starts_with($arg, '--module=')) {
        $moduleFiltersRaw[] = substr($arg, 9);
        continue;
    }
    if (str_starts_with($arg, '--modules=')) {
        $moduleFiltersRaw[] = substr($arg, 10);
    }
}
foreach (['BC_MODULE', 'BC_INSTALLER_MODULE'] as $envVar) {
    $val = getenv($envVar);
    if ($val !== false && $val !== '') {
        $moduleFiltersRaw[] = $val;
    }
}
foreach (['BC_MODULES', 'BC_INSTALLER_MODULES'] as $envVar) {
    $val = getenv($envVar);
    if ($val !== false && $val !== '') {
        $moduleFiltersRaw[] = $val;
    }
}
$normalizeModuleToken = static function (string $value): string {
    $value = strtolower(trim($value));
    if ($value === '') return '';
    $value = preg_replace('/\s+/', '', $value) ?? $value;
    $value = str_replace('_', '-', $value);
    return $value;
};
$moduleFilterCanonical = [];
$moduleFilterDisplay = [];
$canonicalizeModuleToken = static function (string $value) use ($normalizeModuleToken): string {
    $normalized = $normalizeModuleToken($value);
    if ($normalized === '') return '';
    if (str_starts_with($normalized, 'table-')) {
        $normalized = substr($normalized, 6);
    }
    return $normalized;
};
foreach ($moduleFiltersRaw as $rawFilter) {
    foreach (preg_split('/[,\s]+/', $rawFilter) as $token) {
        $canonical = $canonicalizeModuleToken($token ?? '');
        if ($canonical === '') continue;
        if (!array_key_exists($canonical, $moduleFilterCanonical)) {
            $moduleFilterCanonical[$canonical] = false;
            $moduleFilterDisplay[$canonical] = [];
        }
        $tokenLabel = trim((string)$token);
        if ($tokenLabel !== '' && !in_array($tokenLabel, $moduleFilterDisplay[$canonical], true)) {
            $moduleFilterDisplay[$canonical][] = $tokenLabel;
        }
    }
}
$cliRepairOn   = in_array('--repair', $argvList, true) || in_array('-r', $argvList, true);
$cliRepairOff  = in_array('--no-repair', $argvList, true);
$envRepair     = getenv('BC_REPAIR'); // '1' | '0' | false (unset)
$isCI          = (getenv('CI') === 'true') || (getenv('GITHUB_ACTIONS') === 'true');

// TTY detection without posix dependency
$isTty = false;
if (function_exists('stream_isatty')) {
    $isTty = @stream_isatty(STDOUT);
} elseif (function_exists('posix_isatty')) {
    $isTty = @posix_isatty(STDOUT);
}

// Decision
$effective = null; // '1' nebo '0'
if ($envRepair !== false && $envRepair !== '') {
    $effective = ((string)$envRepair === '1' || strtolower((string)$envRepair) === 'true') ? '1' : '0';
} elseif ($cliRepairOn || $cliRepairOff) {
    $effective = $cliRepairOn ? '1' : '0';
} else {
    // Autodetect: when interactive (TTY) and not in CI -> enable repair
    $effective = ($isTty && !$isCI) ? '1' : '0';
}

// Propagate into the environment
putenv('BC_REPAIR=' . $effective);
$_ENV['BC_REPAIR'] = $effective;

// Optional quiet info only in interactive mode
if ($isTty) {
    fwrite(STDERR, "[info] BC_REPAIR={$effective}" . PHP_EOL);
}

/* ---------- Locate all module classes ---------- */
$modules = []; // [FQN => ['pkg'=>string, 'deps'=>string[], 'obj'=>ModuleInterface]]

$pattern = realpath(__DIR__ . '/../../packages');
if ($pattern === false) { fwrite(STDERR, "packages/ not found.\n"); exit(2); }

$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($pattern, FilesystemIterator::SKIP_DOTS));
foreach ($it as $f) {
    if ($f->isFile() && preg_match('~/packages/([^/]+)/src/([A-Za-z0-9_]+)Module\.php$~', $f->getPathname(), $m)) {
        $pkgDir = $m[1]; // e.g., "email-verifications" or "book_categories"
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
        // skip if the module does not support the dialect
        if (!in_array($dialect->value, $obj->dialects(), true)) continue;
        $modules[$class] = [
            'pkg'        => $pkgDir,      // e.g., "email-verifications"
            'pkg_pascal' => $pkgPascal,   // e.g., "EmailVerifications"
            'deps'       => $obj->dependencies(),
            'obj'        => $obj
        ];
    }
}
if (!$modules) { fwrite(STDERR, "No modules discovered.\n"); exit(4); }

/* ---------- Topological ordering by dependencies ---------- */
$graph = [];
$inDeg = [];
foreach ($modules as $fqn => $meta) {
    $graph[$fqn] = [];
    $inDeg[$fqn] = 0;
}
foreach ($modules as $fqn => $meta) {
    foreach ($meta['deps'] as $depName) {
        // expect format 'table-<snake>' => convert to FQN
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
    $remaining = array_diff(array_keys($modules), $order);
    $details = [];
    foreach ($remaining as $rem) {
        $deps = $modules[$rem]['deps'] ?? [];
        $details[] = $rem . ' => [' . implode(', ', $deps) . ']';
    }
    fwrite(STDERR, "Dependency cycle detected among modules. Remaining: " . implode(' | ', $details) . "\n");
    exit(5);
}

/* ---------- Optional module filter ---------- */
if (!empty($moduleFilterCanonical)) {
    $selected = [];
    foreach ($order as $fqn) {
        $meta = $modules[$fqn];
        /** @var ModuleInterface $obj */
        $obj = $meta['obj'];
        $candidates = [
            $obj->name(),
            preg_replace('/^table[-_]/', '', $obj->name()) ?? '',
            $meta['pkg'],
            $meta['pkg_pascal'],
            $fqn
        ];
        $hit = false;
        foreach ($candidates as $candidate) {
            $key = $canonicalizeModuleToken((string)$candidate);
            if ($key === '') continue;
            if (array_key_exists($key, $moduleFilterCanonical)) {
                $hit = true;
                $moduleFilterCanonical[$key] = true;
            }
        }
        if ($hit) {
            $selected[] = $fqn;
        }
    }
    if (!$selected) {
        fwrite(STDERR, "[error] module filter matched zero modules.\n");
        exit(6);
    }
    $order = $selected;
    $missing = array_keys(array_filter($moduleFilterCanonical, fn($found) => $found === false));
    if ($missing) {
        $labels = [];
        foreach ($missing as $canon) {
            $labels[] = $moduleFilterDisplay[$canon] ? implode('|', $moduleFilterDisplay[$canon]) : $canon;
        }
        fwrite(STDERR, "[warn] module filter did not match: " . implode(', ', $labels) . "\n");
    }
    $selectedNames = array_map(fn($fqn) => $modules[$fqn]['obj']->name(), $order);
    fwrite(STDERR, "[info] module filter active – running " . count($order) . " module(s): " . implode(', ', $selectedNames) . "\n");
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

    // Optional idempotent second run
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
            // after uninstall the view should be gone while the table remains
            $st = $m->status($db, $dialect);
            $okViewGone = empty($st['view']);
            $okTableStay= !empty($st['table']);
            if (!$okViewGone || !$okTableStay) {
                $fail++;
                fwrite(STDERR, "[FAIL][uninstall] {$m->name()} ".
                    json_encode(['view_gone'=>$okViewGone,'table_present'=>$okTableStay,'raw'=>$st], JSON_UNESCAPED_SLASHES)."\n");
            }
            // reinstall so subsequent jobs are unaffected
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
