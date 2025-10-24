<?php
declare(strict_types=1);

namespace BlackCat\Database;

use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Database\Installer;

/**
 * Vysoká vrstva nad Installerem:
 * - single-flight přes advisory lock (aby se nemigrovalo paralelně)
 * - transakční „co jde“
 * - timeouty/izolace/slow-log přes Database helpery
 */
final class Orchestrator
{
    public function __construct(
        private Runtime $rt
    ) {}

    public function installOrUpgradeAll(Registry $registry): void
    {
        $db = $this->rt->db();
        $dialect = $this->rt->dialect();
        $inst = new Installer($db, $dialect);

        $db->withAdvisoryLock('schema:migrate', 30, function() use ($inst, $registry, $db) {
            // pro jistotu zkrátit statement timeout při CI
            $db->withStatementTimeout(60_000, function() use ($inst, $registry) {
                $registry->installOrUpgradeAll($inst);
                return null;
            });
            return null;
        });
    }

    /** Vrátí status všech registrovaných modulů + sumarizaci */
    public function status(Registry $registry): array
    {
        $db = $this->rt->db();
        $dialect = $this->rt->dialect();
        $inst = new Installer($db, $dialect);

        $mods = $registry->all();
        $st = $inst->status($mods);

        $summary = ['total'=>count($mods), 'needsInstall'=>0, 'needsUpgrade'=>0];
        foreach ($st as $row) {
            if ($row['needsInstall']) $summary['needsInstall']++;
            if ($row['needsUpgrade']) $summary['needsUpgrade']++;
        }
        return ['modules'=>$st, 'summary'=>$summary, 'dbId'=>$db->id(), 'serverVersion'=>$db->serverVersion()];
    }

    /** Jednotlivý modul (např. v develop režimu) */
    public function installOrUpgradeOne(ModuleInterface $m): void
    {
        $db = $this->rt->db();
        $dialect = $this->rt->dialect();
        $inst = new Installer($db, $dialect);

        $db->withAdvisoryLock('schema:migrate', 30, function() use ($inst, $m, $db) {
            $db->withStatementTimeout(60_000, function() use ($inst, $m) {
                $inst->installOrUpgrade($m);
                return null;
            });
            return null;
        });
    }
}
