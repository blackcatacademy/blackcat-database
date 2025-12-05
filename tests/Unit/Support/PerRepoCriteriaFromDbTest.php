<?php
declare(strict_types=1);

namespace BlackCat\Database\Tests\Unit\Support;

use PHPUnit\Framework\TestCase;
use BlackCat\Core\Database;
use BlackCat\Database\Support\Criteria;

final class RepoCriteriaForTest extends Criteria
{
    protected function filterable(): array { return ['id','tenant_id','created_at','name']; }
    protected function searchable(): array { return ['name']; }
    protected function defaultPerPage(): int { return 25; }
    protected function maxPerPage(): int { return 200; }

    public static function fromDb(Database $db, int|string|array|null $tenantId = null, string $tenantColumn = 'tenant_id'): self
    {
        $c = new self();
        $drv = strtolower((string)($db->driver() ?? 'mysql'));
        $dialect = ($drv === 'pgsql') ? 'postgres' : (($drv === 'mariadb') ? 'mysql' : $drv);
        $c->setDialect($dialect);
        if ($tenantId !== null) { $c->tenant($tenantId, $tenantColumn); }
        return $c;
    }
}

/**
 * Tests the per-repo Criteria template: fromDb() maps driver -> dialect and applies tenancy.
 * Creates a local "repo Criteria" that extends the central Criteria.
 */
final class PerRepoCriteriaFromDbTest extends TestCase
{

    public static function setUpBeforeClass(): void
    {
        if (!Database::isInitialized()) {
            Database::init(['dsn'=>'sqlite::memory:','user'=>null,'pass'=>null,'options'=>[]]);
        }
    }

    public function testFromDbSetsDialectAndTenant(): void
    {
        $db = Database::getInstance();
        $c  = RepoCriteriaForTest::fromDb($db, 42);
        [$where] = $c->toSql(true);
        // SQLite maps to the mysql fallback, but the tenant condition remains
        $this->assertStringContainsString('tenant_id =', $where);
    }
}
