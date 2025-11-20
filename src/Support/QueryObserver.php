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

/**
 * SQL query observer (start/stop) with read-replica routing info.
 *
 * Usage:
 *  - {@see onQueryStart()} is invoked immediately before the query is sent.
 *  - {@see onQueryEnd()}   is invoked after completion; on failure $ms === null and $err carries the exception.
 *
 * Conventions:
 *  - $route indicates the chosen route per router: {@see QueryObserver::ROUTE_PRIMARY} | {@see QueryObserver::ROUTE_REPLICA}.
 *  - $ms is the duration in milliseconds (float, may include decimals) or null on error.
 */
interface QueryObserver
{
    /** Primary database (write). */
    public const ROUTE_PRIMARY = 'primary';

    /** Replica (read). */
    public const ROUTE_REPLICA = 'replica';

    /**
     * Notification right before the query executes.
     *
     * @param string                $sql     Original SQL (may include observability comment).
     * @param array<string,mixed>   $params  Query parameters (values may be scalars/arrays/DateTime…).
     * @param string                $route   {@see QueryObserver::ROUTE_PRIMARY} | {@see QueryObserver::ROUTE_REPLICA}
     */
    public function onQueryStart(string $sql, array $params, string $route): void;

    /**
     * Notification after the query finishes.
     *
     * @param string                $sql     Original SQL.
     * @param array<string,mixed>   $params  Query parameters.
     * @param float|null            $ms      Duration in ms; null if an exception occurred.
     * @param \Throwable|null       $err     Exception when failure occurs (otherwise null).
     * @param string                $route   {@see QueryObserver::ROUTE_PRIMARY} | {@see QueryObserver::ROUTE_REPLICA}
     */
    public function onQueryEnd(string $sql, array $params, ?float $ms, ?\Throwable $err, string $route): void;
}
