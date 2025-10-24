<?php
declare(strict_types=1);

namespace BlackCat\Database\Contracts;

use BlackCat\Core\Database;
use BlackCat\Database\SqlDialect;

/**
 * Minimální, stabilní kontrakt implementovaný každým balíčkem (submodule).
 * Umbrella vrstvy (Installer/Registry) na něm staví orchestraci.
 */
interface ModuleInterface
{
    /** Jednoznačný identifikátor, např. "table-products". */
    public function name(): string;

    /** Fyzická tabulka, např. "products". */
    public function table(): string;

    /** SemVer verze schématu modulu, např. "1.0.0". */
    public function version(): string;

    /** @return list<'mysql'|'postgres'> Povolené dialekty. */
    public function dialects(): array;

    /**
     * Soft závislosti (names jiných balíčků), např. ['table-categories'].
     * @return list<string>
     */
    public function dependencies(): array;

    /** Počáteční instalace schématu modulu. */
    public function install(Database $db, SqlDialect $d): void;

    /** Upgrade schématu z verze $from na current version(). */
    public function upgrade(Database $db, SqlDialect $d, string $from): void;

    /**
     * Odinstalace „kontraktu“ (view) – tabulka zůstává zachována.
     * Používají na to testy a CI smoke test.
     */
    public function uninstall(Database $db, SqlDialect $d): void;

    /**
     * Rychlý stav (table/view/idx/fk/ver…) – neměl by házet, spíš vracet zjištěná fakta.
     * Klíče: table(bool), view(bool), missing_idx(string[]), missing_fk(string[]), version(string)
     */
    public function status(Database $db, SqlDialect $d): array;

    /**
     * Strojově čitelné info pro výpočet checksumu (Installer).
     * Typicky: ['table'=>..., 'view'=>..., 'columns'=>string[], 'version'=>...]
     */
    public function info(): array;

    /**
     * Název kontraktního view (staticky kvůli snadné introspekci v nástrojích/testech).
     */
    public static function contractView(): string;
}
