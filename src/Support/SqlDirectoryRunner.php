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
 * Run all SQL scripts in a directory for the selected dialect.
 *
 * Features:
 * - Supports file names NNN_name.<dial>.sql and *_<dial>.sql (backwards compatible).
 * - Stable ordering: numeric prefix first (any length), then case-insensitive alphabetical.
 * - Each file is split via SqlSplitter and executed through DdlSafe::exec().
 * - No module logic or tokens.
 * - Best-effort logging when Database exposes a PSR-3 logger.
 *
 * @psalm-type FileFilter = null|callable(string):bool
 */
final class SqlDirectoryRunner
{
    /**
     * @param FileFilter $filter Optional filter for files (true = include).
     */
    public static function run(Database $db, SqlDialect $d, string $directory, ?callable $filter = null): void
    {
        $logger = null;
        try { $logger = $db->getLogger(); } catch (\Throwable) {}

        $dir = rtrim($directory, "/\\");
        if ($dir === '' || !is_dir($dir)) {
            if ($logger) $logger->warning('SqlDirectoryRunner: directory not found or invalid', ['dir' => $directory]);
            return;
        }

        // Normalize dialect into two branches (mysql|postgres)
        $dial = $d->isMysql() ? 'mysql' : 'postgres';

        // glob without ordering – sort deterministically ourselves
        $pattern1 = $dir . "/*." . $dial . ".sql";
        $pattern2 = $dir . "/*_" . $dial . ".sql";

        $files = array_merge(
            glob($pattern1, GLOB_NOSORT) ?: [],
            glob($pattern2, GLOB_NOSORT) ?: []
        );

        if (!$files) {
            if ($logger) $logger->info('SqlDirectoryRunner: no files matched', ['dir' => $dir, 'dial' => $dial]);
            return;
        }

        // Unique paths (just in case)
        $files = array_values(array_unique(array_map(static fn(string $p) => (string) $p, $files)));

        // Optional filter
        if ($filter) {
            $files = array_values(array_filter($files, static fn(string $p) => (bool) $filter($p)));
        }

        // Sort by (numericPrefix, basename); numericPrefix = first number in name; missing => INF
        usort($files, static function (string $a, string $b): int {
            [$na, $ba] = self::orderKey($a);
            [$nb, $bb] = self::orderKey($b);
            return $na <=> $nb ?: strnatcasecmp($ba, $bb);
        });

        if ($logger) {
            $logger->info('SqlDirectoryRunner: executing SQL directory', [
                'dir'   => $dir,
                'dial'  => $dial,
                'count' => count($files),
            ]);
        }

        // Process files
        foreach ($files as $path) {
            $base = basename($path);
            // Views are handled by Installer::replayViewsScript; skip here to avoid missing-dependency failures
            if (preg_match('/^040_views\./', $base)) {
                if ($logger) { $logger->debug('SqlDirectoryRunner: skipping views file', ['file' => $path]); }
                continue;
            }

            $sql = @file_get_contents($path);
            if ($sql === false) {
                if ($logger) $logger->warning('SqlDirectoryRunner: unable to read file', ['file' => $path]);
                continue;
            }

            // Strip UTF-8 BOM
            if (strncmp($sql, "\xEF\xBB\xBF", 3) === 0) {
                $sql = substr($sql, 3);
            }

            if ($logger) {
                $logger->debug('SqlDirectoryRunner: running file', ['file' => $path]);
            }

            foreach (SqlSplitter::split($sql, $d) as $stmt) {
                $stmt = trim($stmt);
                if ($stmt === '') {
                    continue;
                }
                // DdlSafe::exec() is idempotent/tolerant of common duplicates
                DdlSafe::exec($db, $d, $stmt);
            }
        }
    }

    /**
     * Compute the sort key: [numericPrefix, basename].
     * numericPrefix = first digit sequence at the beginning of the file name (before any separator),
     *                 missing prefix → large number (non-numbered files go last).
     * @return array{0:int,1:string}
     */
    private static function orderKey(string $path): array
    {
        $base = basename($path);
        // Allow "001_", "001-" etc.; when no prefix is present use a large number
        if (preg_match('/^(\d+)/', $base, $m) === 1) {
            return [(int) $m[1], $base];
        }
        return [PHP_INT_MAX, $base];
    }
}
