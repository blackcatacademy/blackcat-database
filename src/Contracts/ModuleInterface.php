<?php
declare(strict_types=1);

namespace BlackCat\Database\Contracts;

use BlackCat\Core\Database\Database;
use BlackCat\Database\SqlDialect;

/**
 * Minimální, stabilní kontrakt, který musí implementovat každý balíček (submodul).
 * Generator v submodulech s tímto rozhraním počítá a umbrella na něm staví orchestrace.
 */
interface ModuleInterface
{
    /** Jednoznačný identifikátor balíčku, např. "table-products". */
    public function name(): string;

    /** Fyzická tabulka, např. "products". */
    public function table(): string;

    /** SemVer verze schématu tohoto balíčku, např. "1.0.0". */
    public function version(): string;

    /** Povolené dialekty (např. ['mysql','postgres']). */
    public function dialects(): array;

    /**
     * Soft závislosti (names jiných balíčků), např. ['table-categories'].
     * Budou respektovány při instalaci/upgradu více modulů najednou.
     */
    public function dependencies(): array;

    /** Počáteční instalace schématu balíčku. */
    public function install(Database $db, SqlDialect $d): void;

    /** Upgrade schématu z verze $from na aktuální version(). */
    public function upgrade(Database $db, SqlDialect $d, string $from): void;

    /**
     * Rychlý stav – volitelně může vracet diff/info, které modul umí nabídnout.
     * Není to závazné API – umbrella s tím zachází opatrně.
     */
    public function status(Database $db, SqlDialect $d): array;

    /**
     * Strojově čitelné info o schématu (sloupce, indexy, FK, views…),
     * používá se pro výpočet checksumu v registru schémat.
     */
    public function info(): array;
}
