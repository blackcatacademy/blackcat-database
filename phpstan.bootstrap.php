<?php

declare(strict_types=1);

$memoryLimit = getenv('PHPSTAN_MEMORY_LIMIT') ?: '1024M';

if (function_exists('ini_set')) {
    @ini_set('memory_limit', $memoryLimit);
}

$autoloadPath = __DIR__ . '/vendor/autoload.php';

if (! file_exists($autoloadPath)) {
    fwrite(STDERR, "Composer autoloader not found at {$autoloadPath}\n");
    exit(1);
}

require $autoloadPath;
