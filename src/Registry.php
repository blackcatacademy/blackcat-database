<?php
declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Database\Contracts\ModuleInterface;

final class Registry
{
    /** @var array<string, ModuleInterface> */
    private array $modules = [];

    public function __construct(ModuleInterface ...$modules)
    {
        foreach ($modules as $m) { $this->register($m); }
    }

    public function register(ModuleInterface $m): void
    {
        $this->modules[$m->name()] = $m;
    }

    /** @return ModuleInterface[] */
    public function all(): array
    {
        return array_values($this->modules);
    }

    public function get(string $name): ?ModuleInterface
    {
        return $this->modules[$name] ?? null;
    }

    /** Projde status všech registrovaných modulů. */
    public function status(Installer $installer): array
    {
        return $installer->status($this->all());
    }

    /** Spustí install/upgrade všech registrovaných modulů (s dependency řazením). */
    public function installOrUpgradeAll(Installer $installer): void
    {
        $installer->installOrUpgradeAll($this->all());
    }
}
