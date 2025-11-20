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

namespace BlackCat\Database\Contracts;

use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;

/**
 * @api
 *
 * Contract for migratable modules (table + view) that work across SQL dialects.
 * Implementations must be idempotent, deterministic, and safe under concurrent runs
 * (for example, multiple application instances deploying simultaneously).
 *
 * Design goals:
 * - Stable, minimal API for install/upgrade/uninstall.
 * - Clear diagnostics via {@see status()}.
 * - Cross-dialect portability (MySQL/PostgreSQL) with explicit capability declarations.
 *
 * Type aliases for static analysis:
 * @phpstan-type Dialect 'mysql'|'postgres'
 * @phpstan-type StatusResult array{
 *   table: bool,
 *   view: bool,
 *   missing_idx?: list<string>,
 *   missing_fk?: list<string>,
 *   version?: string
 * }
 * @phpstan-type InfoMap array<string,mixed>
 *
 * @psalm-type Dialect = 'mysql'|'postgres'
 * @psalm-type StatusResult = array{
 *   table: bool,
 *   view: bool,
 *   missing_idx?: list<string>,
 *   missing_fk?: list<string>,
 *   version?: string
 * }
 * @psalm-type InfoMap = array<string,mixed>
 */
interface ModuleInterface
{
    /** String identifiers of supported dialects (useful in CLI/help output). */
    public const DIALECT_MYSQL    = 'mysql';
    public const DIALECT_POSTGRES = 'postgres';

    /** @return non-empty-string Unique module name used for logging/observability. */
    public function name(): string;

    /**
     * Logical table name (unquoted; implementations are responsible for quoting).
     *
     * @return non-empty-string
     */
    public function table(): string;

    /**
     * Module schema version (SemVer or any deterministic string).
     * It should change only when DDL changes occur.
     *
     * @return non-empty-string
     */
    public function version(): string;

    /**
     * Declares which SQL dialects the module supports.
     *
     * @return list<Dialect>
     */
    public function dialects(): array;

    /**
     * Optional dependencies on other modules (by name or FQCN).
     * Installers should ensure ordering/validation when dependencies are declared.
     *
     * @return list<string>
     */
    public function dependencies(): array;

    /**
     * Idempotent schema installation (DDL, indexes, views, seed data).
     *
     * @throws \Throwable for unrecoverable issues (permissions, corrupted schema, ...)
     */
    public function install(Database $db, SqlDialect $d): void;

    /**
     * Performs an upgrade from a specific version (may include migration steps).
     * Implementations should rely on transactions, write locks, or advisory locks.
     *
     * @param non-empty-string $from version being upgraded from
     * @throws \Throwable for unrecoverable issues
     */
    public function upgrade(Database $db, SqlDialect $d, string $from): void;

    /**
     * Idempotent uninstall (DROP VIEW/TABLE/INDEX ...). Missing objects should be tolerated.
     *
     * @throws \Throwable for unrecoverable issues
     */
    public function uninstall(Database $db, SqlDialect $d): void;

    /**
     * Diagnostics of module state inside the database.
     * - `table` / `view`: existence flags
     * - `missing_idx`: symbolic names/definitions of missing indexes
     * - `missing_fk`: symbolic names of missing foreign keys
     * - `version`: detected version (if the module can provide one)
     *
     * @return StatusResult
     */
    public function status(Database $db, SqlDialect $d): array;

    /**
     * Optional module metadata: column/index/FK definitions, view names, install notes, etc.
     *
     * @return InfoMap
     */
    public function info(): array;

    /**
     * Name of the contract view (unquoted). Implementations should use safe quoting when building SQL.
     *
     * @return non-empty-string
     */
    public static function contractView(): string;
}
