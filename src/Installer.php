<?php
declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\ModuleInterface;

final class Installer
{
    public function __construct(
        private Database $db,
        private SqlDialect $dialect
    ) {}

    public function ensureRegistry(): void
    {
        $ddl = $this->dialect->isMysql()
            ? "CREATE TABLE IF NOT EXISTS _schema_registry (
                 module_name  VARCHAR(200) PRIMARY KEY,
                 version      VARCHAR(20)  NOT NULL,
                 installed_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                 checksum     VARCHAR(64)  NOT NULL
               )"
            : "CREATE TABLE IF NOT EXISTS _schema_registry (
                 module_name  VARCHAR(200) PRIMARY KEY,
                 version      VARCHAR(20)  NOT NULL,
                 installed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                 checksum     VARCHAR(64)  NOT NULL
               )";

        $this->db->exec($ddl);                   // <— Core má nově exec()
    }

    private function isInstalled(string $name): bool {
        return $this->getVersion($name) !== null;
    }

    private function assertDependenciesInstalled(ModuleInterface $m): void {
        $missing = [];
        foreach ($m->dependencies() as $dep) {
            if (!$this->isInstalled($dep)) { $missing[] = $dep; }
        }
        if ($missing) {
            $list = implode(', ', $missing);
            throw new \RuntimeException(
                "Cannot install '{$m->name()}' – missing dependencies: {$list}. ".
                "Run installOrUpgradeAll([...]) with all modules in one go."
            );
        }
    }

    public function installOrUpgrade(ModuleInterface $m): void
    {
        $this->ensureRegistry();

        $supported = $m->dialects();
        if ($supported && !in_array($this->dialect->value, $supported, true)) {
            throw new \RuntimeException("Module {$m->name()} does not support dialect {$this->dialect->value}");
        }

        $current = $this->getVersion($m->name());

        // Nové: pokud ještě není v registry, musí mít nainstalované závislosti
        if ($current === null) {
            $this->assertDependenciesInstalled($m);
            $m->install($this->db, $this->dialect);
        } elseif (version_compare($current, $m->version(), '<')) {
            // upgrade může závislosti teoreticky taky vyžadovat – zkontroluj rovněž
            $this->assertDependenciesInstalled($m);
            $m->upgrade($this->db, $this->dialect, $current);
        }

        $this->upsertVersion($m);
    }

    /** @param ModuleInterface[] $modules */
    public function installOrUpgradeAll(array $modules): void
    {
        $this->ensureRegistry();
        foreach ($this->toposort($modules) as $m) {
            $this->installOrUpgrade($m);
        }
    }

    /** @param ModuleInterface[] $modules */
    public function status(array $modules): array
    {
        $out = [];
        foreach ($modules as $m) {
            $name = $m->name();
            $installed = $this->getVersion($name);
            $target    = $m->version();

            $needsInstall = ($installed === null);
            $needsUpgrade = ($installed !== null && version_compare($installed, $target, '<'));

            $modStatus = [];
            try { $modStatus = $m->status($this->db, $this->dialect); } catch (\Throwable) {}

            $out[$name] = [
                'module'        => $name,
                'table'         => $m->table(),
                'installed'     => $installed,
                'target'        => $target,
                'needsInstall'  => $needsInstall,
                'needsUpgrade'  => $needsUpgrade,
                'dialects'      => $m->dialects(),
                'dependencies'  => $m->dependencies(),
                'checksum'      => $this->computeChecksum($m),
                'moduleStatus'  => $modStatus,
            ];
        }
        return $out;
    }

    // ---------- interní pomocníci ----------

    private function getVersion(string $name): ?string
    {
        $sql = "SELECT version FROM _schema_registry WHERE module_name = :name";
        $val = $this->db->fetchOne($sql, [':name' => $name]);     // <— alias v Core
        return $val !== null ? (string)$val : null;
    }

    private function upsertVersion(ModuleInterface $m): void
    {
        $chk = $this->computeChecksum($m);

        if ($this->dialect->isMysql()) {
            $sql = "INSERT INTO _schema_registry(module_name,version,checksum)
                    VALUES(:name,:version,:checksum)
                    ON DUPLICATE KEY UPDATE version=VALUES(version), checksum=VALUES(checksum)";
        } else {
            $sql = "INSERT INTO _schema_registry(module_name,version,checksum)
                    VALUES(:name,:version,:checksum)
                    ON CONFLICT (module_name)
                    DO UPDATE SET version=EXCLUDED.version, checksum=EXCLUDED.checksum";
        }

        $this->db->execute($sql, [
            ':name'     => $m->name(),
            ':version'  => $m->version(),
            ':checksum' => $chk,
        ]);
    }

    private function computeChecksum(ModuleInterface $m): string
    {
        $payload = json_encode($m->info(), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        return hash('sha256', $payload ?: '');
    }

    /** @return ModuleInterface[] */
    private function toposort(array $modules): array
    {
        $byName = [];
        foreach ($modules as $m) { $byName[$m->name()] = $m; }

        $visited = $temp = [];
        $out = [];

        $visit = function (string $name) use (&$visit, &$visited, &$temp, &$out, $byName): void {
            if (isset($visited[$name])) return;
            if (isset($temp[$name])) throw new \RuntimeException("Dependency cycle detected at '$name'.");
            if (!isset($byName[$name])) { $visited[$name] = true; return; }

            $temp[$name] = true;
            foreach ($byName[$name]->dependencies() as $dep) { $visit($dep); }
            unset($temp[$name]);
            $visited[$name] = true;
            $out[] = $byName[$name];
        };

        foreach (array_keys($byName) as $n) { $visit($n); }
        return $out;
    }
}
