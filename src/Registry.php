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

namespace BlackCat\Database;

use BlackCat\Database\Contracts\ModuleInterface;

/**
 * Module registry with collision protection and convenient iteration helpers.
 */
final class Registry implements \IteratorAggregate, \Countable
{
    /** @var array<string, ModuleInterface> */
    private array $modules = [];

    private bool $locked = false;
    // TODO(crypto-integrations): When crypto manifests export required DatabaseIngressAdapter
    // hooks, wire them through this registry so every module automatically advertises its
    // encryption map + adapter dependencies to installers/runtime tools.

    public function __construct(ModuleInterface ...$modules)
    {
        foreach ($modules as $module) {
            $this->register($module);
        }
    }

    /**
     * Registers a module.
     *
     * @throws \InvalidArgumentException when the name is empty or a duplicate (unless $replace is true)
     */
    public function register(ModuleInterface $module, bool $replace = false): void
    {
        $this->assertNotLocked();

        $name = trim($module->name());
        if ($name === '') {
            throw new \InvalidArgumentException('Module name must not be empty.');
        }

        if (!$replace && $this->has($name)) {
            throw new \InvalidArgumentException("Module '{$name}' is already registered.");
        }

        $this->modules[$name] = $module;
    }

    /** Unregisters a module (idempotent). */
    public function unregister(string $name): void
    {
        $this->assertNotLocked();
        unset($this->modules[$name]);
    }

    /** Locks the registry against further changes (optional). */
    public function lock(): void
    {
        $this->locked = true;
    }

    public function isLocked(): bool
    {
        return $this->locked;
    }

    /** @return list<ModuleInterface> modules in registration order */
    public function all(): array
    {
        return array_values($this->modules);
    }

    public function get(string $name): ?ModuleInterface
    {
        return $this->modules[$name] ?? null;
    }

    /** @throws \OutOfBoundsException when the module is not registered */
    public function getOrFail(string $name): ModuleInterface
    {
        $module = $this->get($name);
        if ($module === null) {
            throw new \OutOfBoundsException("Module '{$name}' is not registered.");
        }

        return $module;
    }

    public function has(string $name): bool
    {
        return isset($this->modules[$name]);
    }

    /** @return list<string> names of registered modules (registration order) */
    public function names(): array
    {
        return array_keys($this->modules);
    }

    public function status(Installer $installer): array
    {
        return $installer->status($this->all());
    }

    public function installOrUpgradeAll(Installer $installer): void
    {
        $installer->installOrUpgradeAll($this->all());
    }

    /** Convenience helper for installing/upgrading a single module by name. */
    public function installOrUpgradeOne(string $name, Installer $installer): void
    {
        $installer->installOrUpgrade($this->getOrFail($name));
    }

    /** IteratorAggregate */
    public function getIterator(): \Traversable
    {
        return new \ArrayIterator($this->all());
    }

    /** Countable */
    public function count(): int
    {
        return \count($this->modules);
    }

    private function assertNotLocked(): void
    {
        if ($this->locked) {
            throw new \LogicException('Registry is locked and cannot be modified.');
        }
    }
}
