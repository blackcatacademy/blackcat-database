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

/**
 * Minimal and stable CRUD/pagination/locking contract shared across packages.
 *
 * Goals:
 * - Consistent PK representations (simple and composite) and row payloads.
 * - Stronger annotations for static analysis (phpstan/psalm).
 * - Safer interfaces (SensitiveParameter on data-bearing inputs).
 *
 * @template-contravariant TCriteria of object
 * @template TRow of array<string,mixed> = array<string,mixed>
 *
 * @phpstan-type Scalar int|float|string|bool
 * @phpstan-type Id int|string|array<string,Scalar|null>|list<Scalar|null>
 * @phpstan-type AssocRow array<string,mixed>
 * @phpstan-type Params array<string,Scalar|null>
 * @phpstan-type PageResult array{
 *   items: list<AssocRow>,
 *   total: int,
 *   page: int,
 *   perPage: int
 * }
 *
 * @psalm-type Scalar = int|float|string|bool
 * @psalm-type Id = int|string|array<string,Scalar|null>|list<Scalar|null>
 * @psalm-type AssocRow = array<string,mixed>
 * @psalm-type Params = array<string,Scalar|null>
 * @psalm-type PageResult = array{
 *   items: list<AssocRow>,
 *   total: int,
 *   page: int,
 *   perPage: int
 * }
 */
interface ContractRepository
{
    /**
     * Updates a row identified by its primary key plus extra WHERE conditions.
     *
     * @param Id $id composite PKs use ['col'=>val,...] or a positional list
     * @param AssocRow $row data to persist
     * @param Params $where additional AND conditions (column => value)
     * @return int number of affected rows
     */
    public function updateByIdWhere(
        int|string|array $id,
        #[\SensitiveParameter] array $row,
        array $where
    ): int;

    /**
     * Inserts a single row.
     *
     * @param AssocRow $row
     */
    public function insert(#[\SensitiveParameter] array $row): void;

    /**
     * Inserts multiple rows in a batch.
     *
     * @param list<AssocRow> $rows
     */
    public function insertMany(#[\SensitiveParameter] array $rows): void;

    /**
     * Performs an UPSERT (INSERT ... ON CONFLICT / ON DUPLICATE KEY UPDATE).
     *
     * @param AssocRow $row
     */
    public function upsert(#[\SensitiveParameter] array $row): void;

    /**
     * Updates a row (or rows) identified by the primary key.
     *
     * @param Id $id
     * @param AssocRow $row
     * @return int number of affected rows
     */
    public function updateById(
        int|string|array $id,
        #[\SensitiveParameter] array $row
    ): int;

    /**
     * Deletes by primary key (soft or hard delete depending on implementation).
     *
     * @param Id $id
     * @return int number of affected rows
     */
    public function deleteById(int|string|array $id): int;

    /**
     * Restores a row by primary key (when soft-delete is supported).
     *
     * @param Id $id
     * @return int number of affected rows
     */
    public function restoreById(int|string|array $id): int;

    /**
     * Fetches a row by its primary key.
     *
     * @param Id $id
     * @return AssocRow|null
     */
    public function findById(int|string|array $id): ?array;

    /**
     * Checks whether any row matches the provided condition.
     *
     * @param non-empty-string $whereSql
     * @param Params $params
     */
    public function exists(
        string $whereSql = '1=1',
        #[\SensitiveParameter] array $params = []
    ): bool;

    /**
     * Counts rows that match the provided condition.
     *
     * @param non-empty-string $whereSql
     * @param Params $params
     */
    public function count(
        string $whereSql = '1=1',
        #[\SensitiveParameter] array $params = []
    ): int;

    /**
     * Domain-specific pagination using a criteria object/value object.
     *
     * @template T of TCriteria
     * @param T $criteria
     * @return PageResult
     *
     * @phpstan-return PageResult
     * @psalm-return PageResult
     */
    public function paginate(object $criteria): array;

    /**
     * Reads and locks a row by primary key (SELECT ... FOR UPDATE).
     * $mode: 'wait' | 'nowait' | 'skip_locked' (implementations may ignore unsupported modes).
     *
     * @param Id $id
     * @param 'wait'|'nowait'|'skip_locked' $mode
     * @return AssocRow|null
     */
    public function lockById(int|string|array $id, string $mode = 'wait'): ?array;
}
