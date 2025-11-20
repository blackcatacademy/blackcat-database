<?php
declare(strict_types=1);

use BlackCat\Core\Database;
use BlackCat\Database\Support\PgCompat;

require __DIR__ . '/../vendor/autoload.php';

/**
 * 1) Deterministically choose the target backend.
 *    - respect BC_DB (normalize it)
 *    - otherwise infer from the presence of a single DSN
 *    - if both DSNs exist and BC_DB is missing -> fail
 *    - if none exist -> fail
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
    $hasMy = (string)((getenv('MYSQL_DSN') ?: getenv('MARIADB_DSN') ?: '')) !== '';

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
        // propagate the decision to env so child processes inherit the same setting
        putenv("BC_DB={$norm}");
    }
    return $norm;
};

$which = $resolveBackend();

/**
 * 2) If the DB is already initialized, do not init again - only validate the match
 *    and set session GUCs (primarily on PG).
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

    // session tuning without re-init
    if ($which === 'pg') {
        $db->exec("SET TIME ZONE 'UTC'");
        $db->exec("SET client_encoding TO 'UTF8'");
        $schema = getenv('BC_PG_SCHEMA') ?: 'public';
        $db->exec("SET search_path TO " . preg_replace('/[^a-z0-9_]/i','', $schema) . ", bc_compat, public");
        // resilience under parallel runs
        $db->exec("SET lock_timeout TO '5s'");
        $db->exec("SET statement_timeout TO '30s'");
        $db->exec("SET idle_in_transaction_session_timeout TO '30s'");
    }

} else {
    /**
     * 3) Initial init based on the resolved backend
     */
    if ($which === 'mysql') {
        $dsn  = getenv('MYSQL_DSN')
            ?: getenv('MARIADB_DSN')
            ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';

        $user = getenv('MYSQL_USER')
            ?: getenv('MARIADB_USER')
            ?: 'root';

        $pass = getenv('MYSQL_PASS')
            ?: getenv('MARIADB_PASS')
            ?: 'root';

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
        if (defined('PDO::MYSQL_ATTR_FOUND_ROWS')) {
            $pdo->setAttribute(PDO::MYSQL_ATTR_FOUND_ROWS, true);
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
                // adjust search_path later after the optional bc_compat install
            ],
        ]);

        $db = Database::getInstance();
        // set timeouts/search_path immediately after connecting (helps parallel runs)
        $db->exec("SET lock_timeout TO '5s'");
        $db->exec("SET statement_timeout TO '30s'");
        $db->exec("SET idle_in_transaction_session_timeout TO '30s'");

        // honor BC_SKIP_COMPAT once, then cleanse it from the process
        $skipCompat = (getenv('BC_SKIP_COMPAT') === '1');

        if (!$skipCompat) {
            // safely serialize bc_compat installation (when the API is available)
            if (method_exists($db, 'withAdvisoryLock')) {
                $db->withAdvisoryLock('bc:compat:install', 10, function() use ($db) {
                    (new PgCompat($db))->install();
                });
            } else {
                (new PgCompat($db))->install();
            }
        }

        // prevent the flag from being inherited by child processes launched from here:
        putenv('BC_SKIP_COMPAT'); // unset inside this process environment
        unset($_ENV['BC_SKIP_COMPAT'], $_SERVER['BC_SKIP_COMPAT']); // also drop it from PHP superglobals

        $schema = getenv('BC_PG_SCHEMA') ?: 'public';
        $db->exec("SET search_path TO " . preg_replace('/[^a-z0-9_]/i','', $schema) . ", bc_compat, public");

    }
}

/**
 * 4) Shared helpers
 */
require __DIR__ . '/support/DbHarness.php';
require __DIR__ . '/support/RowFactory.php';
require __DIR__ . '/support/AssertSql.php';
