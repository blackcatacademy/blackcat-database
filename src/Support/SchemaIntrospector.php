<?php
/*
 *       ####                                
 *      ######                              ██╗    ██╗███████╗██╗      ██████╗ ██████╗ ███╗   ███╗███████╗     
 *     #########                            ██║    ██║██╔════╝██║     ██╔════╝██╔═══██╗████╗ ████║██╔════╝ 
 *    ##########         ##                 ██║ █╗ ██║█████╗  ██║     ██║     ██║   ██║██╔████╔██║█████╗   
 *    ###########      ####                 ██║███╗██║██╔══╝  ██║     ██║     ██║   ██║██║╚██╔╝██║██╔══╝   
 * ###############   ######                 ╚███╔███╔╝███████╗███████╗╚██████╗╚██████╔╝██║ ╚═╝ ██║███████╗
 * ###########  ##  #######                  ╚══╝╚══╝ ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝ 
 * #########    ### #######                  
 * #########     ###  ####                   ██╗  ██╗███████╗██████╗  ██████╗ ██╗ ██████╗███████╗ 
 * ###########    ##    ##                   ██║  ██║██╔════╝██╔══██╗██╔═══██╗██║██╔════╝██╔════╝ 
 * ##########                #               ███████║█████╗  ██████╔╝██║   ██║██║██║     ███████╗ 
 * #######                     ##            ██╔══██║██╔══╝  ██╔══██╗██║   ██║██║██║     ╚════██║ 
 * ##                            ##          ██║  ██║███████╗██║  ██║╚██████╔╝██║╚██████╗███████║ 
 * ######              #######    ##         ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═════╝╚══════╝ 
 * #####            #######  ##   ##       ┌────────────────────────────────────────────────────────────────────────────┐  
 * #####               ####  ##    #         BLACK CAT DATABASE • Arcane Custody Notice                                 │
 * ########             #######    ##        © 2025 Black Cat Academy s. r. o. • All paws reserved.                     │
 * ####                        #     ##      Licensed strictly under the BlackCat Database Proprietary License v1.0.    │
 * ##########                          ##    Evaluation only; commercial rites demand written consent.                  │
 * ####           ######  #        ######    Unauthorized forks or tampering awaken enforcement claws.                  │
 * #####               ##  ##          ##    Reverse engineering, sublicensing, or origin stripping is forbidden.       │
 * ##########   ###  #### ####        #      Liability for lost data, profits, or familiars remains with the summoner.  │
 * ##                 ##  ##       ####      Infringements trigger termination; contact blackcatacademy@protonmail.com. │
 * ###########      ##   # #   ######        Leave this sigil intact—smudging whiskers invites spectral audits.         │
 * #########       #   ##          ##        Governed under the laws of the Slovak Republic.                            │
 * ##############                ###         Motto: “Purr, Persist, Prevail.”                                           │
 * #############    ###############       └─────────────────────────────────────────────────────────────────────────────┘
 */

declare(strict_types=1);

namespace BlackCat\Database\Support;

use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;

/**
 * SchemaIntrospector – safe portable introspection utilities
 * for PostgreSQL and MySQL/MariaDB.
 *
 * Improvements over previous version:
 * - Support qualified names "schema.table" (safe comparison via LOWER()).
 * - Strict object-type filtering (BASE TABLE vs. VIEW).
 * - Postgres: optional detection of materialized views (pg_matviews).
 * - Resilient to null rows + consistent return typing.
 * - Extensions: listColumns(), hasMaterializedView(), hasAnyView().
 */
final class SchemaIntrospector
{
    /* ---------------------------------------------------------------------
     |  PUBLIC API (compatible signatures + extensions)
     | ------------------------------------------------------------------ */

    public static function hasTable(Database $db, SqlDialect $d, string $table): bool
    {
        [$schema, $name] = self::splitQualified($table);

        if ($d->isMysql()) {
            // information_schema.TABLES – TABLE_TYPE='BASE TABLE'
            $sql = "SELECT COUNT(*) FROM information_schema.TABLES
                    WHERE " . ($schema ? "LOWER(TABLE_SCHEMA) = LOWER(:s)" : "TABLE_SCHEMA = DATABASE()") . "
                      AND LOWER(TABLE_NAME) = LOWER(:t)
                      AND TABLE_TYPE = 'BASE TABLE'";
            $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
            return (int)($db->fetchOne($sql, $params) ?? 0) > 0;
        }

        // PostgreSQL – uses current search_path schemas (or explicit schema)
        $sql = "SELECT COUNT(*) FROM information_schema.tables
                WHERE " . ($schema
                    ? "LOWER(table_schema) = LOWER(:s)"
                    : "table_schema = ANY (current_schemas(true))") . "
                  AND table_type = 'BASE TABLE'
                  AND LOWER(table_name) = LOWER(:t)";
        $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
        return (int)($db->fetchOne($sql, $params) ?? 0) > 0;
    }

    public static function hasView(Database $db, SqlDialect $d, string $view): bool
    {
        [$schema, $name] = self::splitQualified($view);

        if ($d->isMysql()) {
            // information_schema.VIEWS existuje v MySQL/MariaDB
            $sql = "SELECT COUNT(*) FROM information_schema.VIEWS
                    WHERE " . ($schema ? "LOWER(TABLE_SCHEMA) = LOWER(:s)" : "TABLE_SCHEMA = DATABASE()") . "
                      AND LOWER(TABLE_NAME) = LOWER(:v)";
            $params = [':v' => $name] + ($schema ? [':s' => $schema] : []);
            return (int)($db->fetchOne($sql, $params) ?? 0) > 0;
        }

        // PostgreSQL – information_schema.views DOES NOT include materialized views
        $sql = "SELECT COUNT(*) FROM information_schema.views
                WHERE " . ($schema
                    ? "LOWER(table_schema) = LOWER(:s)"
                    : "table_schema = ANY (current_schemas(true))") . "
                  AND LOWER(table_name) = LOWER(:v)";
        $params = [':v' => $name] + ($schema ? [':s' => $schema] : []);
        return (int)($db->fetchOne($sql, $params) ?? 0) > 0;
    }

    /**
     * Postgres helper: does the materialized view exist?
     * Always returns false on MySQL/MariaDB (feature unsupported).
     */
    public static function hasMaterializedView(Database $db, SqlDialect $d, string $name): bool
    {
        if ($d->isMysql()) {
            return false;
        }
        [$schema, $view] = self::splitQualified($name);
        $sql = "SELECT COUNT(*) FROM pg_matviews
                WHERE " . ($schema ? "LOWER(schemaname) = LOWER(:s)" : "schemaname = ANY (current_schemas(true))") . "
                  AND LOWER(matviewname) = LOWER(:v)";
        $params = [':v' => $view] + ($schema ? [':s' => $schema] : []);
        return (int)($db->fetchOne($sql, $params) ?? 0) > 0;
    }

    /**
     * "Any" view (regular or materialized – handy on Postgres).
     */
    public static function hasAnyView(Database $db, SqlDialect $d, string $name): bool
    {
        return self::hasView($db, $d, $name)
            || self::hasMaterializedView($db, $d, $name);
    }

    /** @return list<string> */
    public static function listIndexes(Database $db, SqlDialect $d, string $table): array
    {
        [$schema, $name] = self::splitQualified($table);

        if ($d->isMysql()) {
            // STATISTICS: INDEX_NAME – DISTINCT for multi-column indexes
            $sql = "SELECT DISTINCT INDEX_NAME AS idx
                      FROM information_schema.STATISTICS
                     WHERE " . ($schema ? "LOWER(TABLE_SCHEMA) = LOWER(:s)" : "TABLE_SCHEMA = DATABASE()") . "
                       AND LOWER(TABLE_NAME) = LOWER(:t)
                     ORDER BY INDEX_NAME";
            $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
            $rows = (array)$db->fetchAll($sql, $params);
            return array_values(array_map(static fn($r) => (string)$r['idx'], $rows));
        }

        // Postgres: pg_indexes (schema + table)
        $sql = "SELECT indexname AS idx
                  FROM pg_indexes
                 WHERE " . ($schema ? "LOWER(schemaname) = LOWER(:s)" : "schemaname = ANY (current_schemas(true))") . "
                   AND LOWER(tablename) = LOWER(:t)
                 ORDER BY indexname";
        $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
        $rows = (array)$db->fetchAll($sql, $params);
        return array_values(array_map(static fn($r) => (string)$r['idx'], $rows));
    }

    /** @return list<string> */
    public static function listForeignKeys(Database $db, SqlDialect $d, string $table): array
    {
        [$schema, $name] = self::splitQualified($table);

        if ($d->isMysql()) {
            // TABLE_CONSTRAINTS for FK – filter current DB or explicit schema
            $sql = "SELECT tc.CONSTRAINT_NAME AS cn
                      FROM information_schema.TABLE_CONSTRAINTS tc
                     WHERE " . ($schema ? "LOWER(tc.CONSTRAINT_SCHEMA) = LOWER(:s)" : "tc.CONSTRAINT_SCHEMA = DATABASE()") . "
                       AND LOWER(tc.TABLE_NAME) = LOWER(:t)
                       AND tc.CONSTRAINT_TYPE = 'FOREIGN KEY'
                     ORDER BY tc.CONSTRAINT_NAME";
            $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
            $rows = (array)$db->fetchAll($sql, $params);
            return array_values(array_map(static fn($r) => (string)$r['cn'], $rows));
        }

        // Postgres: information_schema.table_constraints pro FK
        $sql = "SELECT constraint_name AS cn
                  FROM information_schema.table_constraints
                 WHERE " . ($schema
                    ? "LOWER(table_schema) = LOWER(:s)"
                    : "table_schema = ANY (current_schemas(true))") . "
                   AND LOWER(table_name) = LOWER(:t)
                   AND constraint_type = 'FOREIGN KEY'
                 ORDER BY constraint_name";
        $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
        $rows = (array)$db->fetchAll($sql, $params);
        return array_values(array_map(static fn($r) => (string)$r['cn'], $rows));
    }

    /**
     * Return list of column names for the table (ordered by ordinal_position).
     *
     * @return list<string>
     */
    public static function listColumns(Database $db, SqlDialect $d, string $table): array
    {
        [$schema, $name] = self::splitQualified($table);

        if ($d->isMysql()) {
            $sql = "SELECT COLUMN_NAME AS col
                      FROM information_schema.COLUMNS
                     WHERE " . ($schema ? "LOWER(TABLE_SCHEMA) = LOWER(:s)" : "TABLE_SCHEMA = DATABASE()") . "
                       AND LOWER(TABLE_NAME) = LOWER(:t)
                     ORDER BY ORDINAL_POSITION";
            $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
            $rows = (array)$db->fetchAll($sql, $params);
            return array_values(array_map(static fn($r) => (string)$r['col'], $rows));
        }

        $sql = "SELECT column_name AS col
                  FROM information_schema.columns
                 WHERE " . ($schema
                    ? "LOWER(table_schema) = LOWER(:s)"
                    : "table_schema = ANY (current_schemas(true))") . "
                   AND LOWER(table_name) = LOWER(:t)
                 ORDER BY ordinal_position";
        $params = [':t' => $name] + ($schema ? [':s' => $schema] : []);
        $rows = (array)$db->fetchAll($sql, $params);
        return array_values(array_map(static fn($r) => (string)$r['col'], $rows));
    }

    /* ---------------------------------------------------------------------
     |  INTERNALS
     | ------------------------------------------------------------------ */

    /**
     * Split qualified name "schema.table" → [schema|null, name].
     * Simple robust approach for common shapes; removes optional quotes/backticks.
     *
     * @return array{0:?string,1:string}
     */
    private static function splitQualified(string $ident): array
    {
        $s = trim($ident);
        // Remove outer backticks/quotes (usually around entire value)
        if ((str_starts_with($s, '`') && str_ends_with($s, '`')) ||
            (str_starts_with($s, '"') && str_ends_with($s, '"'))) {
            $s = substr($s, 1, -1);
        }

        $dot = strpos($s, '.');
        if ($dot === false) {
            return [null, self::stripQuotes($s)];
        }
        $schema = self::stripQuotes(substr($s, 0, $dot));
        $name   = self::stripQuotes(substr($s, $dot + 1));
        return [$schema !== '' ? $schema : null, $name];
    }

    private static function stripQuotes(string $id): string
    {
        $id = trim($id);
        if ($id === '') return $id;

        if ((str_starts_with($id, '`') && str_ends_with($id, '`')) ||
            (str_starts_with($id, '"') && str_ends_with($id, '"'))) {
            return substr($id, 1, -1);
        }
        return $id;
    }
}
