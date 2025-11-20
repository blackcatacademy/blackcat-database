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

/**
 * DbVendor – detects the database vendor/version without tying to a specific PDO driver.
 *
 * Goals:
 *  - Reliably distinguish MySQL vs. MariaDB (including Aurora detection).
 *  - Extract major/minor versions from `SELECT VERSION()` (returns "8.0.36", "10.11.6-MariaDB", ...).
 *  - Never throw exceptions – return reasonable fallbacks on errors.
 *
 * Notes:
 *  - Uses conservative, parameter-less queries (pure introspection).
 *  - `mysqlVersion()` returns [major, minor]; when unknown it defaults to [8, 0].
 */
final class DbVendor
{
    /**
     * Detects whether the server is MariaDB (including ColumnStore, etc.).
     * Heuristic:
     *  - If the driver is not MySQL/MariaDB, return false.
     *  - Try `@@version_comment`, then `VERSION()`, and look for "mariadb" (case-insensitive).
     */
    public static function isMaria(Database $db): bool
    {
        if (!$db->isMysql()) {
            return false;
        }

        try {
            $vc = (string)(self::fetchScalar($db, 'SELECT @@version_comment') ?? '');
            if ($vc === '') {
                $vc = (string)(self::fetchScalar($db, 'SELECT VERSION()') ?? '');
            }
            return \stripos($vc, 'mariadb') !== false;
        } catch (\Throwable) {
            return false;
        }
    }

    /**
     * Rough Aurora MySQL detection (useful for feature flags).
     */
    public static function isAuroraMysql(Database $db): bool
    {
        if (!$db->isMysql()) {
            return false;
        }
        try {
            $vc = (string)(self::fetchScalar($db, 'SELECT @@version_comment') ?? '');
            if ($vc === '') {
                $vc = (string)(self::fetchScalar($db, 'SELECT VERSION()') ?? '');
            }
            return \stripos($vc, 'aurora') !== false;
        } catch (\Throwable) {
            return false;
        }
    }

    /**
     * Returns [major, minor] for MySQL/MariaDB via `SELECT VERSION()`.
     * - Examples: "8.0.36" -> [8,0], "10.5.18-MariaDB" -> [10,5], "5.7.44-log" -> [5,7]
     * - Fallback: [8,0] (conservative default for modern MySQL).
     *
     * @return array{0:int,1:int}
     */
    public static function mysqlVersion(Database $db): array
    {
        $fallback = [8, 0];

        try {
            /** @var string $raw */
            $raw = (string)(self::fetchScalar($db, 'SELECT VERSION()') ?? '');
            if ($raw === '') {
                return $fallback;
            }

            // Grab the first two numeric groups "major.minor"
            if (\preg_match('~(?P<maj>\d+)\.(?P<min>\d+)~', $raw, $m) === 1) {
                $maj = (int)$m['maj'];
                $min = (int)$m['min'];
                return [$maj, $min];
            }
        } catch (\Throwable) {
            // ignore
        }

        return $fallback;
    }

    /**
     * Utility: returns [major, minor] for PostgreSQL.
     * - `SHOW server_version;` or `SELECT current_setting('server_version');`
     * - Examples: "16.3" -> [16,3], "15" -> [15,0]
     *
     * @return array{0:int,1:int}
     */
    public static function postgresVersion(Database $db): array
    {
        $fallback = [14, 0]; // conservative default

        if (!$db->isPg()) {
            return $fallback;
        }

        try {
            $raw = (string)(self::fetchScalar($db, "SHOW server_version") ?? '');
            if ($raw === '') {
                $raw = (string)(self::fetchScalar($db, "SELECT current_setting('server_version')") ?? '');
            }
            if ($raw === '') {
                return $fallback;
            }
            if (\preg_match('~(?P<maj>\d+)(?:\.(?P<min>\d+))?~', $raw, $m) === 1) {
                $maj = (int)$m['maj'];
                $min = isset($m['min']) ? (int)$m['min'] : 0;
                return [$maj, $min];
            }
        } catch (\Throwable) {
            // ignore
        }

        return $fallback;
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    /**
     * Safely retrieves a scalar (string/int/bool...) without relying on a specific Database method.
     * Prefers `fetchValue`, falls back to `fetchOne` when available.
     */
    private static function fetchScalar(Database $db, string $sql): mixed
    {
        // Preferred path (most common API)
        if (\method_exists($db, 'fetchValue')) {
            return $db->fetchValue($sql, [], null);
        }

        // Compatible fallback (some implementations expose fetchOne)
        if (\method_exists($db, 'fetchOne')) {
            /** @var mixed $v */
            $v = $db->fetchOne($sql);
            return $v;
        }

        // Last resort – fetchRow and use the first column
        if (\method_exists($db, 'fetch')) {
            $row = $db->fetch($sql) ?? null;
            if (\is_array($row)) {
                $first = \array_shift($row);
                return $first;
            }
        }

        return null;
    }
}
