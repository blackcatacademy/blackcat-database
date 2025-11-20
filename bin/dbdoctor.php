#!/usr/bin/env php
<?php
declare(strict_types=1);

use BlackCat\Core\Database;

require __DIR__ . '/../vendor/autoload.php';

// Import your project bootstrap here if Database::init() is not invoked automatically.
// require __DIR__ . '/../app/bootstrap.php';

if (!Database::isInitialized()) {
    fwrite(STDERR, "Database not initialized. Run your bootstrap first.\n");
    exit(2);
}

$db = Database::getInstance();

$info = [
    'dsn'     => $db->id(),
    'driver'  => $db->driver(),
    'server'  => $db->serverVersion(),
    'replica' => $db->replicaStatus(),
];

$ok = $db->ping();
$info['ping'] = $ok ? 'ok' : 'fail';

echo json_encode($info, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . PHP_EOL;
exit($ok ? 0 : 1);
