<?php
declare(strict_types=1);

use BlackCat\Core\Database;
use BlackCat\Database\Support\PgCompat;

require __DIR__ . '/../vendor/autoload.php';

/**
 * 1) Deterministicky urči cílový backend.
 *    - respektuj BC_DB (normalizuj)
 *    - jinak odvoď z přítomnosti *jediného* DSN
 *    - pokud jsou oba DSN a BC_DB chybí -> fail
 *    - pokud není žádné -> fail
 */
$resolveBackend = static function (): string {
    $norm = (function (string $v): ?string {
        $v = strtolower(trim($v));
        return match ($v) {
            'mysql', 'mariadb'         => 'mysql',
            'pg', 'pgsql', 'postgres', 'postgresql' => 'pg',
            '', null                   => null,
            default                    => null,
        };
    })(getenv('BC_DB') ?: '');

    $hasPg = (string)(getenv('PG_DSN') ?: '') !== '';
    $hasMy = (string)(getenv('MYSQL_DSN') ?: '') !== '';

    if ($norm === null) {
        if ($hasPg && !$hasMy) {
            $norm = 'pg';
        } elseif ($hasMy && !$hasPg) {
            $norm = 'mysql';
        } elseif ($hasPg && $hasMy) {
            throw new RuntimeException("bootstrap: Ambiguous DB (PG_DSN + MYSQL_DSN set) while BC_DB is unset.");
        } else {
            throw new RuntimeException("bootstrap: No DB configured. Set BC_DB or one of PG_DSN/MYSQL_DSN.");
        }
        // Propaguj rozhodnutí do env, ať child procesy dědí stejné nastavení
        putenv("BC_DB={$norm}");
    }
    return $norm;
};

$which = $resolveBackend();

/**
 * 2) Pokud už je DB initnutá, neinituj znovu – pouze validuj shodu
 *    a nastav session GUCs (hlavně na PG).
 */
if (Database::isInitialized()) {
    $db  = Database::getInstance();
    $pdo = $db->getPdo();
    $drv = (string)$pdo->getAttribute(PDO::ATTR_DRIVER_NAME); // 'mysql' | 'pgsql'

    $mismatch =
        ($which === 'mysql' && $drv !== 'mysql') ||
        ($which === 'pg'    && $drv !== 'pgsql');

    if ($mismatch) {
        throw new RuntimeException("bootstrap: Driver mismatch: BC_DB='{$which}', PDO='{$drv}'.");
    }

    // Session ladění (bez re-initu)
    if ($which === 'pg') {
        $db->exec("SET TIME ZONE 'UTC'");
        $db->exec("SET client_encoding TO 'UTF8'");
        $schema = getenv('BC_PG_SCHEMA') ?: 'public';
        $db->exec("SET search_path TO " . preg_replace('/[^a-z0-9_]/i','', $schema) . ", bc_compat, public");
        // Odolnost v paralelách
        $db->exec("SET lock_timeout TO '5s'");
        $db->exec("SET statement_timeout TO '30s'");
        $db->exec("SET idle_in_transaction_session_timeout TO '30s'");
    }

} else {
    /**
     * 3) První init podle rozhodnutého backendu
     */
    if ($which === 'mysql') {
        $dsn  = getenv('MYSQL_DSN')  ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';
        $user = getenv('MYSQL_USER') ?: 'root';
        $pass = getenv('MYSQL_PASS') ?: 'root';

        Database::init([
            'dsn'    => $dsn,
            'user'   => $user,
            'pass'   => $pass,
            'init_commands' => [
                "SET time_zone = '+00:00'",
            ],
        ]);

        $pdo = Database::getInstance()->getPdo();
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
        if (defined('PDO::MYSQL_ATTR_USE_BUFFERED_QUERY')) {
            $pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false);
        }

    } else { // 'pg'
        $dsn  = getenv('PG_DSN')  ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
        $user = getenv('PG_USER') ?: 'postgres';
        $pass = getenv('PG_PASS') ?: 'postgres';

        Database::init([
            'dsn'    => $dsn,
            'user'   => $user,
            'pass'   => $pass,
            'init_commands' => [
                "SET TIME ZONE 'UTC'",
                "SET client_encoding TO 'UTF8'",
                // search_path doladíme ještě níže po případné instalaci bc_compat
            ],
        ]);

        $db = Database::getInstance();
        // Nastav timeouty/search_path hned po připojení (kvůli paralelám)
        $db->exec("SET lock_timeout TO '5s'");
        $db->exec("SET statement_timeout TO '30s'");
        $db->exec("SET idle_in_transaction_session_timeout TO '30s'");

        // Nainstaluj bc_compat (idempotentní), *pak* nastav finální search_path
        (new PgCompat($db))->install();
        $schema = getenv('BC_PG_SCHEMA') ?: 'public';
        $db->exec("SET search_path TO " . preg_replace('/[^a-z0-9_]/i','', $schema) . ", bc_compat, public");
    }
}

/**
 * 4) Sdílené helpery
 */
require __DIR__ . '/support/DbHarness.php';
require __DIR__ . '/support/RowFactory.php';
require __DIR__ . '/support/AssertSql.php';
