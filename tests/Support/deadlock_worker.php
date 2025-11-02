<?php
declare(strict_types=1);

use BlackCat\Core\Database;

require __DIR__ . '/../ci/bootstrap.php';

/**
 * Args: <table> <updCol> <idA> <idB> <role:A|B>
 */
$argc >= 6 || (fwrite(STDERR, "Args: <table> <updCol> <idA> <idB> <role:A|B>\n") && exit(2));

$table = (string)$argv[1];
$updCol = (string)$argv[2];
$idA = (int)$argv[3];
$idB = (int)$argv[4];
$role = (string)$argv[5];

/* -----------------------------------------------------------
 * 1) Fallback init – když bootstrap DB neotevřel, otevři ji stejně jako v lock_row_repo.php
 * --------------------------------------------------------- */
if (!Database::isInitialized()) {
    @include_once __DIR__ . '/../../vendor/autoload.php';

    $driverRaw = strtolower((string)(getenv('BC_DB') ?: ''));
    if ($driverRaw === '') {
        fwrite(STDERR, "[deadlock_worker] BC_DB not set after bootstrap; refusing to guess.\n");
        exit(8);
    }

    $driver = match ($driverRaw) {
        'mysql','mariadb'                       => 'mysql',
        'pg','pgsql','postgres','postgresql'   => 'pgsql',
        default                                 => '',
    };
    if ($driver === '') {
        fwrite(STDERR, "[deadlock_worker] Unknown BC_DB='{$driverRaw}'. Use mysql|mariadb|pg|pgsql|postgres|postgresql.\n");
        exit(7);
    }

    if ($driver === 'mysql') {
        $dsn  = getenv('MYSQL_DSN')  ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';
        $user = getenv('MYSQL_USER') ?: 'root';
        $pass = getenv('MYSQL_PASS') ?: '';

        Database::init([
            'dsn'    => $dsn,
            'user'   => $user,
            'pass'   => $pass,
            'init_commands' => [
                "SET time_zone = '+00:00'",
            ],
        ]);
    } else { // pgsql
        $dsn  = getenv('PG_DSN')  ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
        $user = getenv('PG_USER') ?: 'postgres';
        $pass = getenv('PG_PASS') ?: '';

        Database::init([
            'dsn'    => $dsn,
            'user'   => $user,
            'pass'   => $pass,
            'init_commands' => [
                "SET TIME ZONE 'UTC'",
            ],
        ]);
    }
}

/* -----------------------------------------------------------
 * 2) Validace shody BC_DB ↔ PDO driver + PG session timeouty
 * --------------------------------------------------------- */
$db  = Database::getInstance();
$pdo = $db->getPdo();

$pdoDriver = (string)$pdo->getAttribute(PDO::ATTR_DRIVER_NAME);  // 'mysql' | 'pgsql'
$envRaw    = strtolower((string)(getenv('BC_DB') ?: ''));
$envNorm   = match ($envRaw) {
    'mysql','mariadb'                       => 'mysql',
    'pg','pgsql','postgres','postgresql'    => 'pgsql',
    default                                 => '',
};
if ($envNorm === '' || $pdoDriver !== $envNorm) {
    fwrite(STDERR, "[deadlock_worker] ENV/driver mismatch: BC_DB(normalized)='{$envNorm}', PDO='{$pdoDriver}'. Aborting.\n");
    exit(7);
}
if ($pdoDriver === 'pgsql') {
    try {
        // krátké limity, ať se případné zablokování rychle vyřeší
        $db->exec("SET lock_timeout = '5s'");
        $db->exec("SET statement_timeout = '30s'");
        $db->exec("SET idle_in_transaction_session_timeout = '30s'");
    } catch (Throwable $_) {}
}

/* -----------------------------------------------------------
 * 3) Deadlock scénář – MUSÍME jet v jedné transakci!
 *    A: lockne A, pak se pokusí locknout B
 *    B: lockne B, pak se pokusí locknout A
 * --------------------------------------------------------- */
try {
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    $qi    = fn(string $x) => $db->quoteIdent($x);
    $idCol = 'id'; // tenhle test vybírá tabulku s PK 'id'

    // *** DŮLEŽITÉ: začni transakci před prvním FOR UPDATE ***
    $pdo->beginTransaction();

    // pro PG ještě lokální lock_timeout, aby druhý krok nevisel dlouho
    if ($pdoDriver === 'pgsql') {
        $pdo->exec("SET LOCAL lock_timeout = '5s'");
    }

    if ($role === 'A') {
        // 1) Zamkni A
        $pdo->prepare(
            "SELECT {$qi($idCol)} FROM {$qi($table)} WHERE {$qi($idCol)}=:id FOR UPDATE"
        )->execute([':id'=>$idA]);

        // Krátké okno pro symetrii
        usleep(150_000);

        // 2) Pokus se zamknout B -> s workerem „B“ vytvoří cyklus
        $pdo->prepare(
            "SELECT {$qi($idCol)} FROM {$qi($table)} WHERE {$qi($idCol)}=:id FOR UPDATE"
        )->execute([':id'=>$idB]);

        $pdo->commit();
        exit(0);
    } else { // role B
        // 1) Zamkni B
        $pdo->prepare(
            "SELECT {$qi($idCol)} FROM {$qi($table)} WHERE {$qi($idCol)}=:id FOR UPDATE"
        )->execute([':id'=>$idB]);

        usleep(150_000);

        // 2) Pokus se zamknout A
        $pdo->prepare(
            "SELECT {$qi($idCol)} FROM {$qi($table)} WHERE {$qi($idCol)}=:id FOR UPDATE"
        )->execute([':id'=>$idA]);

        $pdo->commit();
        exit(0);
    }

} catch (Throwable $e) {
    // Deadlock: PG=40P01, MySQL=40001 (errno 1213)
    $state = ($e instanceof PDOException && isset($e->errorInfo[0])) ? (string)$e->errorInfo[0] : '';
    if ($state === '40P01' || $state === '40001') {
        try { if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack(); } catch (Throwable $_) {}
        fwrite(STDERR, "[deadlock_worker] deadlock detected (SQLSTATE={$state})\n");
        exit(99);
    }

    try { if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack(); } catch (Throwable $_) {}
    fwrite(STDERR, "[deadlock_worker] error: ".get_class($e).": ".$e->getMessage()."\n");
    exit(1);
}
