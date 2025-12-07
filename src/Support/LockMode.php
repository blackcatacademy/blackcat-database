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
 * LockMode – compile the suffix for row-level locks (FOR UPDATE …).
 *
 * Input modes:
 *   - 'wait'        → no suffix (blocking behavior)
 *   - 'nowait'      → append "NOWAIT" (if the DB supports it)
 *   - 'skip_locked' → append "SKIP LOCKED" (if the DB supports it)
 *
 * Dialect support:
 *   - PostgreSQL:     both NOWAIT and SKIP LOCKED (native).
 *   - Oracle MySQL 8+: NOWAIT and SKIP LOCKED.
 *   - MariaDB 10.3+:   SKIP LOCKED (NOWAIT typically no).
 *   - MySQL 5.7/MariaDB < 10.3: no suffix.
 *
 * Note: Returned string starts with a space or is empty – suitable for concatenation after "FOR UPDATE".
 */
final class LockMode
{
    public const MODE_WAIT        = 'wait';
    public const MODE_NOWAIT      = 'nowait';
    public const MODE_SKIP_LOCKED = 'skip_locked';

    /**
     * @param 'wait'|'nowait'|'skip_locked' $mode
     * @return string Suffix with a leading space or an empty string.
     */
    public static function compile(Database $db, string $mode): string
    {
        $m = self::normalizeMode($mode);

        // PostgreSQL – full support
        if ($db->isPg()) {
            return $m === self::MODE_SKIP_LOCKED ? ' SKIP LOCKED'
                 : ($m === self::MODE_NOWAIT     ? ' NOWAIT'      : '');
        }

        // MySQL / MariaDB
        if ($db->isMysql()) {
            // MariaDB: SKIP LOCKED since 10.3+, NOWAIT usually not
            if (DbVendor::isMaria($db)) {
                if ($m === self::MODE_SKIP_LOCKED && self::mariaSupportsSkipLocked($db)) {
                    return ' SKIP LOCKED';
                }
                // Older MariaDB or rejected SKIP LOCKED → no suffix (behaves like WAIT).
                return '';
            }

            // Oracle MySQL 8.0+ (including Aurora MySQL 3.x) – NOWAIT and SKIP LOCKED
            if (self::mysqlSupportsNowaitAndSkip($db)) {
                return $m === self::MODE_SKIP_LOCKED ? ' SKIP LOCKED'
                     : ($m === self::MODE_NOWAIT     ? ' NOWAIT'      : '');
            }
        }

        // Not supported → no suffix
        return '';
    }

    /* --------------------------- internals --------------------------- */

    private static function normalizeMode(string $mode): string
    {
        $m = \strtolower(\trim($mode));
        return \in_array($m, [self::MODE_WAIT, self::MODE_NOWAIT, self::MODE_SKIP_LOCKED], true)
            ? $m
            : self::MODE_WAIT;
        // default "wait" = no suffix
    }

    private static function mariaSupportsSkipLocked(Database $db): bool
    {
        [$maj, $min] = DbVendor::mysqlVersion($db); // works for MariaDB too (e.g., 10.5)
        return ($maj > 10) || ($maj === 10 && $min >= 3); // 10.3+
    }

    private static function mysqlSupportsNowaitAndSkip(Database $db): bool
    {
        // MySQL 8.0+ (Aurora MySQL 3.* is also 8.0). 5.7 does not support it.
        [$maj, ] = DbVendor::mysqlVersion($db);
        return $maj >= 8;
    }
}
