<?php
declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\ModuleInterface;

final class Installer {
    public function __construct(private Database $db, private SqlDialect $dialect) {}

    public function ensureRegistry(): void {
        $ddl = $this->dialect->isMysql()
            ? "CREATE TABLE IF NOT EXISTS _schema_registry (
                 module_name VARCHAR(200) PRIMARY KEY,
                 version     VARCHAR(20)  NOT NULL,
                 installed_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
                 checksum    VARCHAR(64)  NOT NULL
               )"
            : "CREATE TABLE IF NOT EXISTS _schema_registry (
                 module_name  VARCHAR(200) PRIMARY KEY,
                 version      VARCHAR(20)  NOT NULL,
                 installed_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
                 checksum     VARCHAR(64)  NOT NULL
               )";
        $this->db->exec($ddl);
    }

    public function installOrUpgrade(ModuleInterface $m): void {
        $this->ensureRegistry();
        $cur = $this->getVersion($m->name());
        if (!$cur) { $m->install($this->db, $this->dialect); }
        else if (version_compare($cur, $m->version(), '<')) {
            $m->upgrade($this->db, $this->dialect, $cur);
        }
        $this->upsertVersion($m);
    }

    private function getVersion(string $name): ?string {
        $sql = "SELECT version FROM _schema_registry WHERE module_name = ?";
        return $this->db->fetchOne($sql, [$name]) ?: null;
    }

    private function upsertVersion(ModuleInterface $m): void {
        $chk = hash('sha256', json_encode($m->info(), JSON_UNESCAPED_SLASHES));
        if ($this->dialect->isMysql()) {
            $sql = "INSERT INTO _schema_registry(module_name,version,checksum)
                    VALUES(?,?,?)
                    ON DUPLICATE KEY UPDATE version=VALUES(version), checksum=VALUES(checksum)";
        } else {
            $sql = "INSERT INTO _schema_registry(module_name,version,checksum)
                    VALUES($1,$2,$3)
                    ON CONFLICT (module_name) DO UPDATE SET version=EXCLUDED.version, checksum=EXCLUDED.checksum";
        }
        $this->db->execute($sql, [$m->name(), $m->version(), $chk]);
    }
}