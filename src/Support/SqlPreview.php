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

final class SqlPreview
{
    /** Single-line SQL preview – trims whitespace and limits length. */
    public static function preview(string $sql, int $limit = 160): string
    {
        $s = \preg_replace("~\r\n?~", "\n", trim($sql)) ?? '';
        $s = \strtok($s, "\n") ?: $s;
        $s = \preg_replace('~\s+~', ' ', $s) ?? '';
        if (\function_exists('mb_strlen')) {
            return \mb_strlen($s) > $limit ? (\mb_substr($s, 0, $limit) . '…') : $s;
        }
        return \strlen($s) > $limit ? (\substr($s, 0, $limit) . '…') : $s;
    }

    /** First "meaningful" line (skips blank/comment lines) with a length limit. */
    public static function firstLine(string $sql, int $limit = 200): string
    {
        $s = \preg_replace("~\r\n?~", "\n", $sql) ?? '';
        foreach (\explode("\n", (string)$s) as $line) {
            $t = \trim($line);
            if ($t === '' || \str_starts_with($t, '--') || \str_starts_with($t, '#') || \str_starts_with($t, '/*')) {
                continue;
            }
            $t = \preg_replace('~\s+~', ' ', $t) ?? '';
            if (\function_exists('mb_strlen')) {
                return \mb_strlen($t) > $limit ? (\mb_substr($t, 0, $limit) . '…') : $t;
            }
            return \strlen($t) > $limit ? (\substr($t, 0, $limit) . '…') : $t;
        }
        return '';
    }
}
