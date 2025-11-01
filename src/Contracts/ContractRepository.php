<?php
declare(strict_types=1);

namespace BlackCat\Database\Contracts;

/**
 * Globální kontrakt, který musí implementovat každý balíčkový Repository.
 *
 * Držíme se záměrně minimální a stabilní sady metod (CRUD + stránkování + zámek),
 * aby implementace zůstaly jednoduché a testy je uměly detekovat napříč balíčky.
 *
 * Poznámky:
 * - `paginate()` je typováno volně přes objektové kritérium – jednotlivé balíčky
 *   si obvykle definují vlastní Criteria třídu; interface na ní nesmí být závislé.
 * - Návratové tvary (shapes) jsou popsány v PHPDoc, aby nástroje jako Psalm/PHPStan
 *   měly silné typové informace.
 *
 * @template TCriteria of object
 *
 * @psalm-type PageResult = array{
 *     items: list<array<string,mixed>>,
 *     total: int,
 *     page: int,
 *     perPage: int
 * }
 * @phpstan-type PageResult = array{
 *     items: list<array<string,mixed>>,
 *     total: int,
 *     page: int,
 *     perPage: int
 * }
 */
interface ContractRepository
{
    /**
     * Vloží jeden řádek.
     *
     * @param array<string,mixed> $row
     */
    public function insert(array $row): void;

    /**
     * Vloží více řádků v jednom statementu (kde to dává smysl).
     *
     * @param list<array<string,mixed>> $rows
     */
    public function insertMany(array $rows): void;

    /**
     * Dialekt-safe UPSERT.
     *
     * @param array<string,mixed> $row
     */
    public function upsert(array $row): void;

    /**
     * UPDATE podle primárního klíče.
     *
     * Má-li tabulka verzi pro optimistic locking, očekává, že
     * do $row můžeš poslat i aktuální hodnotu verze (na kterou se udělá podmínka).
     *
     * @param int|string|array        $id  Složené PK: asociativní ['col'=>val,...] nebo poziční pole.
     * @param array<string,mixed>     $row
     * @return int počet změněných řádků
     */
    public function updateById(int|string|array $id, array $row): int;

    /**
     * Smaže řádek dle PK; pokud je povoleno soft-delete, provede soft-delete.
     *
     * @param int|string|array $id
     * @return int počet změněných/ovlivněných řádků
     */
    public function deleteById(int|string|array $id): int;

    /**
     * Obnoví soft-smazaný řádek dle PK (pokud tabulka soft-delete podporuje).
     *
     * @param int|string|array $id
     * @return int počet změněných/ovlivněných řádků
     */
    public function restoreById(int|string|array $id): int;

    /**
     * Najde řádek dle PK (respektuje soft-delete guard).
     *
     * @param int|string|array $id
     * @return array<string,mixed>|null
     */
    public function findById(int|string|array $id): ?array;

    /**
     * Ověří existenci řádku dle WHERE.
     *
     * @param string                   $whereSql
     * @param array<string,scalar|null> $params
     */
    public function exists(string $whereSql = '1=1', array $params = []): bool;

    /**
     * Vrátí COUNT(*) dle WHERE.
     *
     * @param string                   $whereSql
     * @param array<string,scalar|null> $params
     */
    public function count(string $whereSql = '1=1', array $params = []): int;

    /**
     * Stránkování přes kritéria konkrétního balíčku.
     *
     * @template T of TCriteria
     * @param T $criteria
     * @return array{items: list<array<string,mixed>>, total:int, page:int, perPage:int}
     * @psalm-return PageResult
     * @phpstan-return PageResult
     */
    public function paginate(object $criteria): array;

    /**
     * Přečte a zamkne řádek dle PK (SELECT … FOR UPDATE) pro transakční práci.
     *
     * @param int|string|array $id
     * @return array<string,mixed>|null
     */
    public function lockById(int|string|array $id): ?array;
}
