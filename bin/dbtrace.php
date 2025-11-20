#!/usr/bin/env php
<?php
declare(strict_types=1);

use BlackCat\Core\Database;

require __DIR__ . '/../vendor/autoload.php';

// Ensure your application bootstrap called Database::init(...).
// require __DIR__ . '/../app/bootstrap.php';

if (!Database::isInitialized()) {
    fwrite(STDERR, "Database not initialized. Ensure your bootstrap calls Database::init().\n");
    exit(2);
}

$db = Database::getInstance();
$last = $db->getLastQueries();

echo json_encode($last, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . PHP_EOL;
