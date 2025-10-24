<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

/**
 * Usage:
 *   php tests/support/lock_row_repo.php "<RepoFqn>" <id> <seconds>
 *
 * Pomocný proces:
 *  - inicializuje DB z env (BC_DB, DSN atd.)
 *  - přes Repository::lockById($id) drží zámek <seconds> sekund
 *  - transakci pak ROLLBACK (nechceme měnit data)
 */

require __DIR__ . '/../ci/bootstrap.php';

use BlackCat\Core\Database;

if ($argc < 4) {
    fwrite(STDERR, "Args: <RepoFqn> <id> <seconds>\n");
    exit(2);
}
$repoFqn = $argv[1];
$id      = (int)$argv[2];
$secs    = (int)$argv[3];

if (!class_exists($repoFqn)) {
    // pokus o autoload (Composer dev autoloader by měl být k dispozici)
    // ve většině případů stačí require definic:
    $parts = explode('\\', $repoFqn);
    $pkg   = $parts[count($parts)-2] ?? null; // ...\Packages\<Pkg>\Repository
    if ($pkg) {
        $def = "BlackCat\\Database\\Packages\\{$pkg}\\Definitions";
        if (class_exists($def)) { /* OK */ }
    }
    if (!class_exists($repoFqn)) {
        fwrite(STDERR, "Repository class not found: $repoFqn\n");
        exit(3);
    }
}

$db = Database::getInstance();
$pdo = $db->getPdo();
$pdo->beginTransaction();

$repo = new $repoFqn($db);
$row  = $repo->lockById($id); // SELECT ... FOR UPDATE
if (!$row) {
    fwrite(STDERR, "Row not found, id=$id\n");
    $pdo->rollBack();
    exit(4);
}

// Drž zámek po dobu $secs
sleep(max(1, $secs));

// Uklid — nechceme měnit stav
$pdo->rollBack();
