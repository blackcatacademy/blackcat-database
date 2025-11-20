# How-to: Tenant scope & Criteria

`TenantScope` (`src/Tenancy/TenantScope.php`) centralizes tenant filtering so every repository/service enforces the same rules. It works with the shared `Criteria` builder or plain SQL statements.

## 1. Guard reads via Criteria

```php
use BlackCat\Database\Support\Criteria;
use BlackCat\Database\Tenancy\TenantScope;

$scope = new TenantScope([42, 43]); // accept a single ID or a list

$crit = (new Criteria())
    ->setDialectFromDatabase($db)
    ->withDatabase($db)
    ->softDelete('deleted_at')
    ->orderByTable('created_at', 'DESC');

$scope->apply($crit, 'tenant_id');        // adds WHERE tenant_id IN (...)
[$where, $params, $order, $limit, $offset, $joins] = $crit->toSql(['alias' => 't']);
```

`Criteria::tenant()` is also available inside generated Criteria subclasses, so calling `$crit->tenant($scope->idList())` keeps the filter whitelisted.

## 2. Patch raw SQL

```php
$tenant = new TenantScope(7);
$params = [];

$sql = <<<SQL
SELECT * FROM invoices t
WHERE status = :status
SQL;

$sql = $tenant->appendToWhere($sql, $params, $db, 't.tenant_id');
$params[':status'] = 'open';

$stmt = $db->prepare($sql);
$stmt->execute($params);
```

`appendToWhere()` detects whether the statement already contains a `WHERE` clause and injects the tenant predicate with quoted identifiers + unique placeholders.

## 3. Enforce tenants on writes

```php
$scope = new TenantScope(99);

$row = [
    'tenant_id' => 99,
    'title'     => 'Example'
];

$scope->guardRow($row);     // throws if tenant_id mismatches the scope
// or rely on auto-attach for single-tenant scopes
$row = $scope->attach(['title' => 'Safe']); // tenant_id = 99 is injected

$rows = $scope->attachMany($bulkRows);      // bulk variant, still validates ids
```

- Multi-tenant scopes (arrays) require the caller to pass an explicit `tenant_id`; `attach()` will throw if it cannot disambiguate.
- `guardIds()` is helpful when deleting/restoring multiple rows: `$scope->guardIds($idList)` ensures every target belongs to the active tenant(s).

## 4. Working with JSON / custom columns

`TenantScope::sql()` returns the raw fragment if you need to combine it with JSON predicates or uncommon column names:

```php
$scope = new TenantScope(['east', 'west']);
$piece = $scope->sql('postgres', 'payload ->> \'tenant\'', '__json_tenant');

$sql = '... WHERE ' . $piece['expr'] . ' AND payload->>\'status\' = :status';
$params = $piece['params'] + [':status' => 'active'];
```

Use `sqlSafe()` whenever possible so identifiers are quoted by the active driver. Pair these helpers with repository-level guards (custom base classes or dedicated Criteria wrappers) to keep tenancy enforcement automatic.
