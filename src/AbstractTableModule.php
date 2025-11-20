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

namespace BlackCat\Database\Support;

use BlackCat\Database\SqlDialect;
use BlackCat\Database\Contracts\ModuleInterface;
use BlackCat\Database\Support\SqlIdentifier as Ident;
use BlackCat\Database\Support\SqlDirectoryRunner;
use BlackCat\Database\Support\SchemaIntrospector;
use BlackCat\Core\Database;

/**
 * Reusable base for table-backed modules. Intended to eliminate repeated boilerplate
 * in per-table module classes, while keeping exact behavior consistent.
 */
abstract class AbstractTableModule implements ModuleInterface
{
    abstract protected function tableName(): string;
    abstract protected static function contractViewName(): string;
    abstract protected function moduleVersion(): string;

    /** Directory containing this module's SQL scripts (default: "<subclass-dir>/schema"). */
    protected function schemaDir(): string
    {
        $rc = new \ReflectionClass($this);
        return \dirname((string)$rc->getFileName()) . '/schema';
    }

    /** @return string[] */
    protected function supportedDialects(): array { return ['mysql', 'postgres']; }
    /** @return string[] */
    protected function moduleDependencies(): array { return []; }

    public function name(): string { return 'table-' . $this->tableName(); }
    public function table(): string { return $this->tableName(); }
    public function version(): string { return $this->moduleVersion(); }

    /** @return string[] */
    public function dialects(): array { return $this->supportedDialects(); }
    /** @return string[] */
    public function dependencies(): array { return $this->moduleDependencies(); }

    public static function contractView(): string
    {
        // Avoid calling subclass constructors with deps; construct w/o ctor.
        $rc  = new \ReflectionClass(static::class);
        /** @var self $tmp */
        $tmp = $rc->newInstanceWithoutConstructor();
        return $tmp->contractViewName();
    }

    public function install(Database $db, SqlDialect $d): void
    {
        $dir = $this->schemaDir();
        if (is_dir($dir)) {
            SqlDirectoryRunner::run($db, $d, $dir);
        }

        $table = Ident::qi($db, $this->table());
        $view  = Ident::qi($db, $this->contractViewName());

        // DdlGuard: lock + retry + view verification (used for MySQL/MariaDB)
        (new DdlGuard($db, $d, $db->getLogger()))->applyCreateView(
            "CREATE VIEW {$view} AS SELECT * FROM {$table}",
            [
                'lockTimeoutSec'      => (int)($_ENV['BC_INSTALLER_LOCK_SEC'] ?? 15),
                'retries'             => (int)($_ENV['BC_INSTALLER_VIEW_RETRIES'] ?? 3),
                'fenceMs'             => (int)($_ENV['BC_VIEW_FENCE_MS'] ?? 600),
                'dropFirst'           => true,         // consistent behavior even without OR REPLACE
                'normalizeOrReplace'  => true,         // strip "OR REPLACE" from the input statement
                'ignoreDefinerDrift'  => true,         // safe across environments (dev/prod)
            ]
        );
    }

    public function upgrade(Database $db, SqlDialect $d, string $from): void
    {
        // hook for data migrations
    }

    public function uninstall(Database $db, SqlDialect $d): void
    {
        $qiV    = Ident::qi($db, $this->contractViewName());
        $suffix = $d->isMysql() ? '' : ' CASCADE';   // allow CASCADE on PostgreSQL, keep empty elsewhere
        $sql    = "DROP VIEW IF EXISTS {$qiV}{$suffix}";
        try {
            $db->execWithMeta($sql, [], [
                'svc'  => 'installer',
                'op'   => 'drop_view',
                'view' => $this->contractViewName(),
            ]);
        } catch (\Throwable) {
            // no-op
        }
    }

    public function status(Database $db, SqlDialect $d): array
    {
        $table = $this->table();
        $view  = $this->contractViewName();

        $hasTable = SchemaIntrospector::hasTable($db, $d, $table);
        $hasView  = SchemaIntrospector::hasView($db, $d, $view);

        $haveIdx = SchemaIntrospector::listIndexes($db, $d, $table);
        $haveFk  = SchemaIntrospector::listForeignKeys($db, $d, $table);
        $wantIdx = $this->expectedIndexes();
        $wantFk  = $this->expectedForeignKeys();
        $missingIdx = array_values(array_diff($wantIdx, $haveIdx));
        $missingFk  = array_values(array_diff($wantFk, $haveFk));

        return [
            'table'       => $hasTable,
            'view'        => $hasView,
            'missing_idx' => $missingIdx,
            'missing_fk'  => $missingFk,
            'have_idx'    => $haveIdx,
            'have_fk'     => $haveFk,
            'version'     => $this->version(),
        ];
    }

    public function info(): array
    {
        return [
            'table'   => $this->table(),
            'view'    => $this->contractViewName(),
            'version' => $this->version(),
        ];
    }

    /** @return string[] expected index names (override if you want status diffing) */
    protected function expectedIndexes(): array { return []; }
    /** @return string[] expected foreign key names (override if you want status diffing) */
    protected function expectedForeignKeys(): array { return []; }
}
