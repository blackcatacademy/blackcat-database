<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Support;

use BlackCat\Core\Database;

final class ConnFactory
{
    private static function normalizeDb(?string $v): ?string
    {
        $v = strtolower(trim((string)$v));
        return match ($v) {
            'mysql', 'mariadb'                         => 'mysql',
            'pg', 'pgsql', 'postgres', 'postgresql'    => 'pg',
            ''                                         => null,
            default                                    => null,
        };
    }

    private static function resolveBackend(): string
    {
        $norm  = self::normalizeDb(getenv('BC_DB') ?: '');
        $hasPg = (string)(getenv('PG_DSN') ?: '') !== '';
        $hasMy = (string)(getenv('MYSQL_DSN') ?: '') !== '';

        if ($norm === null) {
            if ($hasPg && !$hasMy) {
                $norm = 'pg';
            } elseif ($hasMy && !$hasPg) {
                $norm = 'mysql';
            } elseif ($hasPg && $hasMy) {
                throw new \RuntimeException("ConnFactory: Ambiguous DB (PG_DSN + MYSQL_DSN set) while BC_DB is unset.");
            } else {
                throw new \RuntimeException("ConnFactory: No DB configured. Set BC_DB or one of PG_DSN/MYSQL_DSN.");
            }
            // propagate so child processes inherit the same decision
            putenv("BC_DB={$norm}");
        }

        // If Database is already initialized, align with the actual PDO driver
        if (class_exists(Database::class) && Database::isInitialized()) {
            $pdo     = Database::getInstance()->getPdo();
            $drv     = (string)$pdo->getAttribute(\PDO::ATTR_DRIVER_NAME); // 'mysql' | 'pgsql'
            $drvNorm = $drv === 'mysql' ? 'mysql' : ($drv === 'pgsql' ? 'pg' : $drv);
            if ($drvNorm !== $norm) {
                // Prevent cross-backend mix: prefer the already-initialized driver
                $norm = $drvNorm;
                putenv("BC_DB={$norm}");
            }
        }
        return $norm;
    }

    public static function newPdo(): \PDO
    {
        $which = self::resolveBackend();

        if ($which === 'mysql') {
            $dsn  = getenv('MYSQL_DSN')  ?: 'mysql:host=127.0.0.1;port=3306;dbname=test;charset=utf8mb4';
            $user = getenv('MYSQL_USER') ?: 'root';
            $pass = getenv('MYSQL_PASS') ?: 'root';

            $pdo = new \PDO($dsn, $user, $pass, [
                \PDO::ATTR_ERRMODE            => \PDO::ERRMODE_EXCEPTION,
                \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
                \PDO::ATTR_EMULATE_PREPARES   => false,
            ]);
            if (defined('PDO::MYSQL_ATTR_USE_BUFFERED_QUERY')) {
                $pdo->setAttribute(\PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false);
            }
            $pdo->exec("SET time_zone = '+00:00'");
            return $pdo;
        }

        // Postgres
        $dsn   = getenv('PG_DSN')  ?: 'pgsql:host=127.0.0.1;port=5432;dbname=test';
        $user  = getenv('PG_USER') ?: 'postgres';
        $pass  = getenv('PG_PASS') ?: 'postgres';

        $pdo = new \PDO($dsn, $user, $pass, [
            \PDO::ATTR_ERRMODE            => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
            \PDO::ATTR_EMULATE_PREPARES   => false,
        ]);

        // Zarovnej session s bootstrapem
        $pdo->exec("SET TIME ZONE 'UTC'");
        $pdo->exec("SET client_encoding TO 'UTF8'");
        $schema = getenv('BC_PG_SCHEMA') ?: 'public';
        $safe   = preg_replace('/[^a-z0-9_]/i', '', $schema);
        $pdo->exec("SET search_path TO {$safe}, bc_compat, public");

        // Prevent parallel runs from hanging indefinitely
        $pdo->exec("SET lock_timeout TO '10s'");
        $pdo->exec("SET statement_timeout TO '30s'");
        $pdo->exec("SET idle_in_transaction_session_timeout TO '30s'");

        return $pdo;
    }

    public static function setShortLockTimeout(\PDO $pdo, int $ms = 1000): void
    {
        $drv = (string)$pdo->getAttribute(\PDO::ATTR_DRIVER_NAME);
        if ($drv === 'mysql') {
            $sec = max(1, (int)ceil($ms / 1000));
            $pdo->exec("SET innodb_lock_wait_timeout = {$sec}");
            // safer behavior on timeout
            try { $pdo->exec("SET SESSION innodb_rollback_on_timeout = 1"); } catch (\Throwable $e) {}
            return;
        }
        if ($drv === 'pgsql') {
            $sql = $pdo->inTransaction()
                ? "SET LOCAL lock_timeout = '{$ms}ms'"
                : "SET lock_timeout = '{$ms}ms'";
            $pdo->exec($sql);
            return;
        }
        throw new \RuntimeException("Unknown PDO driver: {$drv}");
    }
}
