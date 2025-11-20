<?php
declare(strict_types=1);

namespace BlackCat\Database\Modules;

use BlackCat\Core\Database;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Database\SqlDialect;

final class SyncAuditModule implements ModuleInterface
{
    public function name(): string { return 'sync_audit'; }
    public function table(): string { return 'sync_audit'; }
    public function version(): string { return '1.0.0'; }
    public function dialects(): array { return [self::DIALECT_MYSQL, self::DIALECT_POSTGRES]; }
    public function dependencies(): array { return []; }

    public function install(Database $db, SqlDialect $d): void
    {
        if ($d->isMysql()) {
            $db->exec('CREATE TABLE IF NOT EXISTS sync_audit (
                id BIGINT PRIMARY KEY AUTO_INCREMENT,
                link VARCHAR(128) NOT NULL,
                tenant VARCHAR(128) NULL,
                started_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                status VARCHAR(32) NOT NULL
            )');
        } else {
            $db->exec('CREATE TABLE IF NOT EXISTS sync_audit (
                id BIGSERIAL PRIMARY KEY,
                link TEXT NOT NULL,
                tenant TEXT NULL,
                started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                status TEXT NOT NULL
            )');
        }
    }

    public function upgrade(Database $db, SqlDialect $d, string $from): void
    {
        $this->install($db, $d);
    }

    public function uninstall(Database $db, SqlDialect $d): void
    {
        $db->exec('DROP TABLE IF EXISTS sync_audit');
    }

    public function status(Database $db, SqlDialect $d): array
    {
        if ($d->isMysql()) {
            $exists = (bool)$db->fetchValue('SHOW TABLES LIKE :name', [':name' => $this->table()]);
        } else {
            $exists = $db->fetchValue('SELECT to_regclass(:name)', [':name' => $this->table()]) !== null;
        }
        return ['table' => $exists, 'view' => false, 'version' => $this->version()];
    }

    public function info(): array
    {
        return ['description' => 'Audit table for BlackCat Sync runs.'];
    }

    public static function contractView(): string { return 'sync_audit_view'; }
}
