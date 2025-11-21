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
use BlackCat\Core\DatabaseException;
use BlackCat\Database\SqlDialect;
use BlackCat\Database\Support\DbVendor;

/**
 * DdlSafe – idempotent DDL execution across PostgreSQL / MySQL / MariaDB.
 *
 * Goals:
 * - Tolerate "already exists / does not exist" errors (without exceptions) while not swallowing real DDL errors.
 * - Safely handle identifiers (schema.table, quoting via the driver).
 * - Cross-dialect "ADD CHECK": before CREATE/ALTER first remove the existing CHECK safely.
 * - Zero dependency on modules (no token registry).
 *
 * Note: we intentionally do not start a transaction – some DDL might change or forbid it.
 */
final class DdlSafe
{
    /**
     * Idempotent execution of a single DDL statement.
     */
    public static function exec(Database $db, SqlDialect $d, string $sql): void
    {
        $sqlTrim = self::normalizeSql($sql);
        if ($sqlTrim === '') {
            return;
        }
        $sqlTrim = self::rewriteMariaFunctionalIndex($db, $d, $sqlTrim);

        $traceDdl = (getenv('BC_TRACE_DDL') === '1' || strtolower((string)getenv('BC_TRACE_DDL')) === 'true');
        if ($traceDdl) {
            fwrite(STDERR, "[DDL] " . $sqlTrim . PHP_EOL);
        }

        // 1) Special cross-dialect case: ALTER TABLE ... ADD CONSTRAINT <name> CHECK (...)
        //    -> attempt a preceding DROP (so ADD is idempotent even without IF EXISTS support).
        self::maybeDropExistingCheckBeforeAdd($db, $d, $sqlTrim);

        // 2) Execute the DDL itself (with meta when the DB implementation supports it)
        try {
            if (\method_exists($db, 'execWithMeta')) {
                $db->execWithMeta($sqlTrim, [], ['component' => 'ddlsafe', 'op' => 'exec']);
            } else {
                $db->exec($sqlTrim);
            }
        } catch (DatabaseException $e) {
            // 3) Evaluate whether the error is safely tolerable (idempotent)
            $prev     = $e->getPrevious();
            $msgOuter = \strtolower((string)$e->getMessage());
            $msgInner = \strtolower($prev instanceof \PDOException ? (string)$prev->getMessage() : '');
            $msgAll   = \trim($msgOuter . ' ' . $msgInner);

            $sqlstate = ($prev instanceof \PDOException) ? (string)($prev->errorInfo[0] ?? '') : '';
            $code     = ($prev instanceof \PDOException) ? (int)  ($prev->errorInfo[1] ?? 0)  : 0;
            $errInfo  = ($prev instanceof \PDOException && \is_array($prev->errorInfo)) ? json_encode($prev->errorInfo) : '';
            $preview  = \substr($sqlTrim, 0, 400);
            $len      = \strlen($sqlTrim);

            if (self::isTolerableError($d, $sqlstate, $code, $msgAll)) {
                return; // silently tolerate – idempotent scenario
            }
            fwrite(STDERR, "[DDL][error] sqlstate={$sqlstate} code={$code} msg={$msgAll} sql=" . $sqlTrim . PHP_EOL);
            if ($errInfo) {
                fwrite(STDERR, "[DDL][errorInfo] " . $errInfo . PHP_EOL);
            }
            fwrite(STDERR, "[DDL][stmt] len={$len} preview=" . $preview . PHP_EOL);
            throw $e;
        }
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    private static function normalizeSql(string $sql): string
    {
        $s = \ltrim($sql, "\xEF\xBB\xBF");
        // Normalize CRLF -> LF and trim trailing whitespace
        $s = \preg_replace("~\r\n?~", "\n", $s) ?? $s;
        $s = \preg_replace('~[ \t]+$~m', '', $s) ?? $s;
        $s = \trim($s);
        if ($s !== '' && \substr($s, -1) === ';') {
            $s = \rtrim($s, ";\r\n\t ");
        }
        return $s;
    }

    /**
     * MariaDB 10.4 does not support functional indexes. When we detect a CREATE INDEX
     * using LOWER(col), synthesize a STORED generated column `<col>_ci` and rewrite the
     * index to target that column instead. Best effort: if column already exists, the
     * IF NOT EXISTS guard keeps this idempotent.
     */
    private static function rewriteMariaFunctionalIndex(Database $db, SqlDialect $d, string $sql): string
    {
        if (!$d->isMysql()) { return $sql; }
        if (!DbVendor::isMaria($db)) { return $sql; }
        [$maj, $min] = DbVendor::mysqlVersion($db);
        // MariaDB 10.5+ supports functional indexes; only rewrite for 10.4 and below.
        if ($maj > 10 || ($maj === 10 && $min >= 5)) { return $sql; }

        // Match: CREATE [UNIQUE] INDEX idx ON table (tenant_id, (LOWER(name)))
        $re = '~^\s*CREATE\s+(UNIQUE\s+)?INDEX\s+([`"]?[\w\-]+[`"]?)\s+ON\s+([`"]?[\w\-]+[`"]?)\s*\(\s*([`"]?tenant_id[`"]?)\s*,\s*\(\s*LOWER\(\s*([`"]?)([A-Za-z0-9_]+)\5\s*\)\s*\)\s*\)\s*$~i';
        if (!\preg_match($re, $sql, $m)) { return $sql; }

        $unique = $m[1] ? 'UNIQUE ' : '';
        $indexName = \trim($m[2], '`"');
        $table = \trim($m[3], '`"');
        $col = $m[6];
        $ciCol = $col . '_ci';

        // Best-effort: add generated column for case-insensitive search.
        try {
            $db->exec(
                "ALTER TABLE `{$table}` ADD COLUMN IF NOT EXISTS `{$ciCol}` VARCHAR(255) " .
                "GENERATED ALWAYS AS (LOWER(`{$col}`)) STORED"
            );
        } catch (\Throwable) {
            // keep going; index rewrite may still work if column pre-exists
        }

        return "CREATE {$unique}INDEX `{$indexName}` ON `{$table}` (`tenant_id`, `{$ciCol}`)";
    }

    /**
     * If it's "ALTER TABLE <tab> ADD CONSTRAINT <name> CHECK (...)" try to DROP the same CHECK first
     * (dialect aware and safe).
     */
    private static function maybeDropExistingCheckBeforeAdd(Database $db, SqlDialect $d, string $sqlTrim): void
    {
        if (!\preg_match(
            '~(?is)^\s*ALTER\s+TABLE\s+((?:[`"]?[A-Za-z0-9_]+[`"]?\.)?[`"]?[A-Za-z0-9_]+[`"]?)\s+ADD\s+CONSTRAINT\s+([`"]?[A-Za-z0-9_]+[`"]?)\s+CHECK\s*\(~',
            $sqlTrim,
            $m
        )) {
            return;
        }

        // Extract schema/table + constraint and quote them safely per dialect
        [$rawTable, $rawName] = [$m[1], $m[2]];
        $qiTable = self::quoteQualifiedIdent($db, $rawTable);
        $qiName  = \BlackCat\Database\Support\SqlIdentifier::q($db, \trim($rawName, '\`"'));

        if ($d->isMysql()) {
            // Attempt to find if the CHECK already exists – drop it when present.
            // (Prefer fast introspection to avoid unnecessary exceptions.)
            [$schema, $table] = self::splitQualified($rawTable);
            $params = [
                ':t' => $table,
                ':c' => \trim($rawName, '`"'),
            ];

            $whereSchema = $schema !== null
                ? 'CONSTRAINT_SCHEMA = :s OR CONSTRAINT_SCHEMA = DATABASE()'
                : 'CONSTRAINT_SCHEMA = DATABASE()';

            if ($schema !== null) {
                $params[':s'] = $schema;
            }

            $sqlExists = "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                          WHERE {$whereSchema}
                            AND TABLE_NAME = :t
                            AND CONSTRAINT_NAME = :c
                            AND CONSTRAINT_TYPE = 'CHECK'";

            try {
                /** @var int|string|null $cnt */
                $cnt = $db->fetchValue($sqlExists, $params, 0);
                $exists = (int)$cnt > 0;
            } catch (\Throwable) {
                // Introspection failed → fall back to best-effort drop
                $exists = true;
            }

            if ($exists) {
                // MariaDB uses DROP CONSTRAINT; MySQL 8 uses DROP CHECK
                $isMaria = false;
                try {
                    $isMaria = DbVendor::isMaria($db);
                } catch (\Throwable) {
                    $isMaria = false;
                }

                $dropStmt = $isMaria
                    ? "ALTER TABLE {$qiTable} DROP CONSTRAINT {$qiName}"
                    : "ALTER TABLE {$qiTable} DROP CHECK {$qiName}";

                // Attempt to DROP with fallback (Maria vs. MySQL) – do not throw
                try {
                    $db->exec($dropStmt);
                } catch (\Throwable) {
                    try {
                        $db->exec($isMaria
                            ? "ALTER TABLE {$qiTable} DROP CHECK {$qiName}"
                            : "ALTER TABLE {$qiTable} DROP CONSTRAINT {$qiName}"
                        );
                    } catch (\Throwable) {
                        // Final fallback – ignore; the ADD logic will handle it
                    }
                }
            }
        } else {
            // PostgreSQL: we can use IF EXISTS
            try {
                $db->exec("ALTER TABLE {$qiTable} DROP CONSTRAINT IF EXISTS {$qiName}");
            } catch (\Throwable) {
                // Ignore – this is best-effort idempotency
            }
        }
    }

    /**
     * Return true if the error is a typical "idempotent" case (object already exists / is missing).
     */
    private static function isTolerableError(SqlDialect $d, string $sqlstate, int $code, string $msgAll): bool
    {
        $msgAll = \strtolower($msgAll);

        if ($d->isMysql()) {
            // MySQL/MariaDB – typical codes:
            // 1050 table exists, 1051 unknown table, 1060 duplicate column, 1061 duplicate key name,
            // 1091 can't drop (doesn't exist), 1826 duplicate foreign key, 3822 check exists,
            // 3815 check already exists (newer), 1005/errno:121 rename/dup key on rebuild (idempotent for some DDL).
            if (\in_array($code, [1050,1051,1060,1061,1091,1826,3822,3815], true)) {
                return true;
            }
            if (\str_contains($msgAll, 'already exists')
                || \str_contains($msgAll, 'duplicate')
                || \str_contains($msgAll, 'cannot drop index')
                || \str_contains($msgAll, 'cannot add foreign key constraint')
                || \str_contains($msgAll, 'check constraint') && \str_contains($msgAll, 'exists')
            ) {
                return true;
            }
            // ALTER TABLE rebuild → 1005 + errno:121 / "duplicate key on write or update"
            if ($code === 1005 && (\str_contains($msgAll, 'errno: 121') || \str_contains($msgAll, 'duplicate key on write or update'))) {
                return true;
            }
            return false;
        }

        // PostgreSQL – classic SQLSTATEs for "dup/exists/undefined":
        // 42P07 duplicate_table, 42710 duplicate_object (index/type/sequence/...),
        // 42701 duplicate_column, 42704 undefined_object (drop if not exists),
        // 23505 unique_violation – only if the text explicitly says "already exists" (CREATE INDEX CONCURRENTLY can surface like this).
        if (\in_array($sqlstate, ['42P07','42710','42701','42704'], true)) {
            return true;
        }
        if (\str_contains($msgAll, 'already exists') || \str_contains($msgAll, 'does not exist')) {
            return true;
        }
        return false;
    }

    /** From "schema.table" (with/without quotes/backticks) return [schema|null, table] without quoting. */
    private static function splitQualified(string $ident): array
    {
        $raw = \str_replace(['`','"'], '', \trim($ident));
        if (\strpos($raw, '.') === false) {
            return [null, $raw];
        }
        [$schema, $table] = \explode('.', $raw, 2);
        return [$schema !== '' ? $schema : null, $table];
    }

    /** Safely quote a fully-qualified identifier via the driver (schema.table). */
    private static function quoteQualifiedIdent(Database $db, string $ident): string
    {
        [$schema, $table] = self::splitQualified($ident);
        return $schema !== null
            ? \BlackCat\Database\Support\SqlIdentifier::qi($db, $schema . '.' . $table)
            : \BlackCat\Database\Support\SqlIdentifier::q($db, $table);
    }
}
