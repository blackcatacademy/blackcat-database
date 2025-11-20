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
 * DdlException – domain exception for DDL failures (CREATE/ALTER/DROP/INDEX/GRANT...).
 *
 * Goals:
 * - Wrap low-level driver errors with **context** (SQLSTATE, dialect, object, SQL).
 * - Remain **backwards compatible**: can still be called as `new DdlException($message)`.
 * - Provide **factory** methods for common scenarios (existing object, missing object, privileges, ...).
 *
 * @phpstan-type DdlMeta array<string,mixed>
 */
class DdlException extends DbRuntimeException
{
    /** SQLSTATE code (e.g. '42P07' = duplicate_table in PostgreSQL) */
    private ?string $sqlState;

    /** Logical object name (table/index/constraint/schema...) when available. */
    private ?string $objectName;

    /** Problematic DDL statement (when provided). */
    private ?string $statement;

    /**
     * @param string $message human-readable description
     * @param string|null $sqlState SQLSTATE or vendor code
     * @param string|null $dialect 'postgres'|'mysql'|... (informational)
     * @param string|null $objectName object name (table/index/...)
     * @param string|null $statement problematic DDL statement
     * @param DdlMeta|null $meta contextual metadata
     * @param \Throwable|null $previous previous exception (PDO/driver)
     */
    public function __construct(
        string $message,
        ?string $sqlState = null,
        ?string $dialect = null,
        ?string $objectName = null,
        #[\SensitiveParameter] ?string $statement = null,
        ?array $meta = null,
        ?\Throwable $previous = null
    ) {
        parent::__construct($message, $meta ?? [], $dialect, $previous, 0);
        $this->sqlState   = $sqlState;
        $this->objectName = $objectName;
        $this->statement  = $statement;
    }

    // ---------------------- Factory helpers ----------------------

    /** @param DdlMeta|null $meta */
    public static function objectAlreadyExists(
        string $objectName,
        ?string $dialect = null,
        ?string $sqlState = null,
        #[\SensitiveParameter] ?string $statement = null,
        ?array $meta = null,
        ?\Throwable $previous = null
    ): self {
        $msg = "DDL failed: object already exists: {$objectName}";
        return new self($msg, $sqlState, $dialect, $objectName, $statement, $meta, $previous);
    }

    /** @param DdlMeta|null $meta */
    public static function objectMissing(
        string $objectName,
        ?string $dialect = null,
        ?string $sqlState = null,
        #[\SensitiveParameter] ?string $statement = null,
        ?array $meta = null,
        ?\Throwable $previous = null
    ): self {
        $msg = "DDL failed: object not found: {$objectName}";
        return new self($msg, $sqlState, $dialect, $objectName, $statement, $meta, $previous);
    }

    /** @param DdlMeta|null $meta */
    public static function insufficientPrivilege(
        string $action,
        ?string $objectName = null,
        ?string $dialect = null,
        ?string $sqlState = null,
        #[\SensitiveParameter] ?string $statement = null,
        ?array $meta = null,
        ?\Throwable $previous = null
    ): self {
        $target = $objectName !== null ? " on {$objectName}" : '';
        $msg = "DDL failed: insufficient privilege for {$action}{$target}";
        return new self($msg, $sqlState, $dialect, $objectName, $statement, $meta, $previous);
    }

    /** Generic wrapper for driver exceptions. @param DdlMeta|null $meta */
    public static function fromDriverError(
        \Throwable $e,
        ?string $dialect = null,
        ?string $sqlState = null,
        ?string $objectName = null,
        #[\SensitiveParameter] ?string $statement = null,
        ?array $meta = null
    ): self {
        return new self($e->getMessage(), $sqlState, $dialect, $objectName, $statement, $meta, $e);
    }

    // ---------------------- Accessors ----------------------

    public function sqlState(): ?string { return $this->sqlState; }
    public function dialect(): ?string { return parent::dialect(); }
    public function objectName(): ?string { return $this->objectName; }

    /** Statement should not be logged at INFO/DEBUG without reviewing sensitivity. */
    public function statement(): ?string { return $this->statement; }

    /** @return DdlMeta */
    public function meta(): array { return parent::meta(); }

    /** Simple safe context payload for logging. */
    public function context(): array
    {
        return array_filter([
            'sqlState'   => $this->sqlState,
            'dialect'    => $this->dialect(),
            'object'     => $this->objectName,
            // Statement intentionally omitted for security reasons
            'meta'       => ($m = $this->meta()) ? $m : null,
            'previous'   => $this->getPrevious() ? \get_class($this->getPrevious()) : null,
        ], static fn($v) => $v !== null);
    }
}
