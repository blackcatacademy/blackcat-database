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
 * InstallerException – domain-specific exception for schema registry/module migration errors.
 *
 * Goals:
 * - Clear, actionable error messages plus **meta context** for fast debugging.
 * - Backwards compatibility (originally only `new InstallerException($message)`).
 * - Practical factory methods for common scenarios (dependency cycle, invalid registry, ...).
 *
 * @phpstan-type Meta array<string,mixed>
 */
final class InstallerException extends DbRuntimeException
{
    /**
     * @param string $message human-readable message
     * @param Meta $meta optional context (module, dependencies, dialect, stack, ...)
     * @param int $code optional error code
     * @param \Throwable|null $previous previous exception
     */
    public function __construct(string $message, array $meta = [], int $code = 0, ?\Throwable $previous = null)
    {
        // The dialect may be provided via meta -> forward it to the base class for extra context.
        $dialect = isset($meta['dialect']) && \is_string($meta['dialect']) ? $meta['dialect'] : null;
        parent::__construct($message, $meta, $dialect, $previous, $code);
    }

    /**
     * Appends extra context to the exception (useful when chaining builders).
     * Returns **$this** intentionally for fluent usage.
     *
     * @param Meta $extra
     * @return $this
     */
    public function addMeta(array $extra): self
    {
        $this->meta = [...$this->meta, ...$extra];
        return $this;
    }

    /** Safe context dump suitable for logging. */
    public function context(): array
    {
        return [
            'message' => $this->getMessage(),
            'code'    => $this->getCode(),
            'meta'    => ($m = $this->meta()) ? $m : null,
            'prev'    => $this->getPrevious() ? \get_class($this->getPrevious()) : null,
        ];
    }

    // ---------------------------------------------------------------------
    // Factory helpers (dev-loved, with sensible defaults and readable messages)
    // ---------------------------------------------------------------------

    /**
     * Circular dependency detected in the module graph.
     *
     * @param non-empty-string $at node where the cycle was detected
     * @param list<non-empty-string>|null $cycleStack optional path/stack for diagnostics
     */
    public static function dependencyCycle(string $at, ?array $cycleStack = null): self
    {
        $msg = "Dependency cycle detected at '{$at}'.";
        $meta = ['at' => $at];
        if ($cycleStack) { $meta['stack'] = $cycleStack; }
        return new self($msg, $meta);
    }

    /**
     * Invalid registry/schema configuration.
     *
     * @param string $message detailed explanation (e.g. "missing version for module X")
     * @param Meta $meta optional context (module, keys, ...)
     */
    public static function invalidRegistry(string $message, array $meta = []): self
    {
        return new self("Schema registry error: {$message}", $meta);
    }

    /** Missing module in registry. */
    public static function moduleNotFound(string $module): self
    {
        return new self("Module '{$module}' not found in registry.", ['module' => $module]);
    }

    /** Duplicate registration of the same module. */
    public static function duplicateModule(string $module): self
    {
        return new self("Module '{$module}' registered more than once.", ['module' => $module]);
    }

    /** Missing dependency for a module. */
    public static function missingDependency(string $module, string $dependsOn): self
    {
        return new self(
            "Module '{$module}' requires missing dependency '{$dependsOn}'.",
            ['module' => $module, 'dependsOn' => $dependsOn]
        );
    }

    /** Module does not support the given dialect. */
    public static function incompatibleDialect(string $module, string $dialect): self
    {
        return new self(
            "Module '{$module}' is not compatible with dialect '{$dialect}'.",
            ['module' => $module, 'dialect' => $dialect]
        );
    }

    /** Module installation failed. */
    public static function installFailed(string $module, ?\Throwable $previous = null): self
    {
        return new self("Failed to install module '{$module}'.", ['module' => $module], 0, $previous);
    }

    /** Module upgrade from version A to B failed. */
    public static function upgradeFailed(string $module, string $from, string $to, ?\Throwable $previous = null): self
    {
        return new self(
            "Failed to upgrade module '{$module}' from '{$from}' to '{$to}'.",
            ['module' => $module, 'from' => $from, 'to' => $to],
            0,
            $previous
        );
    }

    /** Module uninstallation failed. */
    public static function uninstallFailed(string $module, ?\Throwable $previous = null): self
    {
        return new self("Failed to uninstall module '{$module}'.", ['module' => $module], 0, $previous);
    }
}
