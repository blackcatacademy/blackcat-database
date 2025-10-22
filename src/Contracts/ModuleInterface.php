<?php
declare(strict_types=1);

namespace BlackCat\Database\Contracts;

use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;

interface ModuleInterface {
    public function name(): string;                   // "table-products"
    public function table(): string;                  // "products"
    public function version(): string;                // "1.0.0"
    public function dialects(): array;                // ['mysql','postgres']
    public function dependencies(): array;            // např. ['table-categories']
    public function install(Database $db, SqlDialect $d): void;
    public function upgrade(Database $db, SqlDialect $d, string $from): void;
    public function status(Database $db, SqlDialect $d): array; // diff, verze
    public function info(): array;                    // columns, idx, FK, views
}
