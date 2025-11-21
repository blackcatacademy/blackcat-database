<?php

declare(strict_types=1);

$memoryLimit = getenv('PHPSTAN_MEMORY_LIMIT') ?: '1024M';

if (function_exists('ini_set')) {
    @ini_set('memory_limit', $memoryLimit);
}

// Prefer local source trees for core/crypto packages to avoid stale vendor copies during static analysis.
$repoRoot = __DIR__;
$coreSrc  = $repoRoot . '/local-blackcat-core/src';
$coreAutoload = $repoRoot . '/local-blackcat-core/vendor/autoload.php';
if (is_file($coreAutoload)) {
    require $coreAutoload;
}
$overrides = [
    'BlackCat\\Core\\'             => $coreSrc,
    'BlackCat\\DatabaseCrypto\\'   => $repoRoot . '/local-blackcat-database-crypto/src',
];
spl_autoload_register(static function (string $class) use ($overrides): void {
    foreach ($overrides as $prefix => $dir) {
        if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
            continue;
        }
        $rel  = substr($class, strlen($prefix));
        $path = $dir . '/' . str_replace('\\', '/', $rel) . '.php';
        if (is_file($path)) {
            require $path;
            return;
        }
    }
}, true, true);

$autoloadPath = __DIR__ . '/vendor/autoload.php';

if (! file_exists($autoloadPath)) {
    fwrite(STDERR, "Composer autoloader not found at {$autoloadPath}\n");
    exit(1);
}

require $autoloadPath;
