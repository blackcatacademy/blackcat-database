# How-to: Bulk UPSERT & UpsertBuilder

BlackCat ships two complementary helpers:

- `BulkUpsertTrait` (`src/BulkUpsertRepository.php`) – drop-in trait for repositories that want batch inserts/updates across PostgreSQL/MySQL/MariaDB with automatic chunking and retries.
- `UpsertBuilder` (`src/Support/UpsertBuilder.php`) – helper for single-row UPSERTs (optionally with `RETURNING`) that handles quoting, placeholders, and vendor quirks.

## 1. Wiring the trait

```php
use BlackCat\Database\Support\BulkUpsertTrait;

final class InventoryRepository implements \BlackCat\Database\Contracts\ContractRepository
{
    use RepositoryHelpers;
    use BulkUpsertTrait;

    // optional override: restrict columns we want to update during conflict
    protected function upsertUpdateColumns(): array
    {
        return ['qty_available', 'updated_at'];
    }
}
```

Requirements:
- The repository must expose `$this->db` (`BlackCat\Core\Database`) and implement `def()` (most generated repos inherit this via `RepositoryHelpers`).
- Definitions should implement `pk()`, `pkColumns()`, `upsertKeys()`, `hasColumn()`, `updatedAtColumn()` so the trait can inspect metadata. Generated `Definitions` already contain these methods.

## 2. Executing a bulk upsert

```php
$repo->upsertMany([
    ['id' => 1, 'tenant_id' => 7, 'qty_available' => 5],
    ['id' => 2, 'tenant_id' => 7, 'qty_available' => 0],
]);
```

The trait:
- Collects all columns seen in the payload, filters them through `Definitions::hasColumn()` and auto-detects conflict keys (`upsertKeys()` → fallback to PK).
- Auto-bumps `updated_at` when the definition exposes the column.
- Chunks the input to respect driver parameter limits (≈30k for PG, 60k for MySQL) and retries transient errors via `Retry::runAdvanced()` with exponential backoff.
- Calls optional hooks: `afterWrite()` and `invalidateSelfCache()` if the repository defines them.

## 3. Single-row UPSERTs with RETURNING

```php
[$sql, $params] = UpsertBuilder::buildRowReturning(
    $db,
    table: 'inventory',
    row: ['id' => 1, 'qty_available' => 10],
    conflictKeys: ['id'],
    updateCols: ['qty_available'],
    updatedAt: 'updated_at',
    returning: ['id', 'qty_available', 'updated_at']
);

$row = $db->fetch($sql, $params);
```

- PostgreSQL requires explicit conflict keys; MySQL/MariaDB deduce them from unique indexes.
- `updatedAt` is optional – when provided the helper injects `CURRENT_TIMESTAMP(6)` unless you already included the column in `updateCols`.
- `addReturning()` is a lower-level helper that appends a `RETURNING` clause only when the server supports it (PG always, MySQL ≥ 8.0.21, MariaDB ≥ 10.5). Call it manually if you need custom SQL.

## 4. Tips & gotchas

- Always sanitize/validate rows before passing them to the trait; it does not coerce data types.
- For MySQL 8.0, the helper uses the `INSERT ... AS _new` alias technique so it can reference the incoming row when `VALUES()` is deprecated. MariaDB still uses `VALUES(column)`.
- When you need per-row hooks (e.g., auditing), wrap `upsertMany()` in a transaction and emit the events yourself. The trait intentionally focuses on fast data-plane writes.
- Combine with `TenantScope` or repository-level guards so multi-tenant tables cannot leak data between tenants during bulk writes.
