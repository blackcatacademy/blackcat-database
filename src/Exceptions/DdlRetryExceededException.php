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

namespace BlackCat\Database\Exceptions;

/**
 * DdlRetryExceededException
 *
 * Thrown when all retry attempts for a DDL operation (CREATE/ALTER/DROP...) have been exhausted.
 * - Keeps the original simple constructor for compatibility.
 * - Populates {@see DdlException} context: `objectName` and `meta['attempts']`.
 */
final class DdlRetryExceededException extends DdlException
{
    public function __construct(
        string $what,
        int $attempts,
        ?\Throwable $prev = null
    ) {
        $msg = "DDL retries exceeded for {$what} (attempts={$attempts})";

        // DdlException::__construct(
        //   string $message,
        //   ?string $sqlState = null,
        //   ?string $dialect = null,
        //   ?string $objectName = null,
        //   ?string $statement = null,
        //   ?array  $meta = null,
        //   ?\Throwable $previous = null
        // )
        parent::__construct(
            $msg,
            null,           // sqlState (unknown)
            null,           // dialect  (unknown)
            $what,          // objectName
            null,           // statement
            ['attempts' => $attempts], // meta
            $prev
        );
    }

    /** Name of the target object (table/index/...) whose retries were exhausted. */
    public function target(): ?string
    {
        return $this->objectName();
    }

    /** Returns the number of attempts stored in meta. */
    public function attempts(): ?int
    {
        $meta = $this->meta();
        return isset($meta['attempts']) ? (int) $meta['attempts'] : null;
    }
}
