<?php
declare(strict_types=1);

$composerAutoload = __DIR__ . '/../../vendor/autoload.php';
if (is_file($composerAutoload)) {
    require_once $composerAutoload;
}

/**
 * PSR-4-ish autoload pro umbrella + submoduly:
 *  - BlackCat\Database\*      -> ./src/...
 *  - BlackCat\Core\*          -> ./src/Core/... (fallback ./core/... ./core/src/...)
 *  - BlackCat\Database\Packages\{Pkg}\... -> ./packages/{Pkg}/src/...
 */
spl_autoload_register(function(string $class): void {
    $class = ltrim($class, '\\');

    $try = function(string $path) {
        if (is_file($path)) { require_once $path; return true; }
        return false;
    };

    // Packages: BlackCat\Database\Packages\{Pkg}\Foo\Bar
    $prefix = 'BlackCat\\Database\\Packages\\';
    if (str_starts_with($class, $prefix)) {
        $rest = substr($class, strlen($prefix));               // {Pkg}\Foo\Bar
        $parts = explode('\\', $rest, 2);
        $pkg   = $parts[0] ?? '';
        $tail  = $parts[1] ?? '';
        if ($pkg !== '' && $tail !== '') {
            $path = __DIR__ . "/../../packages/{$pkg}/src/" . str_replace('\\', '/', $tail) . ".php";
            if ($try($path)) return;
        }
    }

    // Umbrella: BlackCat\Database\...
    $prefix2 = 'BlackCat\\Database\\';
    if (str_starts_with($class, $prefix2)) {
        $tail = substr($class, strlen($prefix2));
        $path = __DIR__ . "/../../src/" . str_replace('\\', '/', $tail) . ".php";
        if ($try($path)) return;
    }

    // Core: BlackCat\Core\...
    $prefix3 = 'BlackCat\\Core\\';
    if (str_starts_with($class, $prefix3)) {
        $tail = substr($class, strlen($prefix3));
        $candidates = [
            __DIR__ . "/../../src/Core/" . str_replace('\\', '/', $tail) . ".php",
            __DIR__ . "/../../src/"      . str_replace('\\', '/', $tail) . ".php",
            __DIR__ . "/../../core/"     . str_replace('\\', '/', $tail) . ".php",
            __DIR__ . "/../../core/src/" . str_replace('\\', '/', $tail) . ".php",
        ];
        foreach ($candidates as $p) { if ($try($p)) return; }
    }
});
