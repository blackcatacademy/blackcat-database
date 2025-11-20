#!/usr/bin/env php
<?php
declare(strict_types=1);

use BlackCat\Core\Database;

require_once __DIR__ . '/../vendor/autoload.php';

function out(mixed $payload): void
{
    if (is_string($payload)) {
        fwrite(STDOUT, $payload . PHP_EOL);
        return;
    }
    fwrite(STDOUT, json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . PHP_EOL);
}

function err(string $message): void
{
    fwrite(STDERR, $message . PHP_EOL);
}

function usage(): void
{
    out(
        "dbctl usage:\n" .
        "  dbctl ping\n" .
        "  dbctl explain '<SQL>' [--analyze]\n" .
        "  dbctl route primary|replica '<SQL>'\n" .
        "  dbctl wait-replica [--ms=1500]\n" .
        "  dbctl trace\n"
    );
}

if ($argc < 2) {
    usage();
    exit(1);
}

$cmd = $argv[1];

// Application bootstrap must have already called Database::init(...)
if (!Database::isInitialized()) {
    err('Database not initialized. Initialize in your bootstrap before using dbctl.');
    exit(2);
}

$db = Database::getInstance();

switch ($cmd) {
    case 'ping':
        out($db->ping() ? 'OK' : 'FAIL');
        break;

    case 'explain':
        $sql = $argv[2] ?? '';
        $analyze = in_array('--analyze', $argv, true);
        out($db->explainPlan($sql, [], $analyze));
        break;

    case 'route':
        $target = $argv[2] ?? '';
        $sql = $argv[3] ?? 'SELECT 1';
        if ($target === 'primary') {
            $result = $db->withPrimary(fn () => $db->fetchAll($sql));
        } elseif ($target === 'replica') {
            $result = $db->withReplica(fn () => $db->fetchAll($sql));
        } else {
            err('route must be primary|replica');
            exit(3);
        }
        out($result);
        break;

    case 'wait-replica':
        $ms = 1500;
        foreach ($argv as $arg) {
            if (str_starts_with($arg, '--ms=')) {
                $ms = (int)substr($arg, 5);
            }
        }
        out($db->waitForReplica($ms) ? 'READY' : 'TIMEOUT');
        break;

    case 'trace':
        out($db->getLastQueries());
        break;

    default:
        usage();
        exit(1);
}
