# How-to: SQL Coverage

1) Tag important SQL in `schema/*.sql` with markers:
```sql
-- region: users.list
SELECT ...;
```

2) Log executed regions from runtime (opt-in):
```php
require __DIR__.'/scripts/support/SqlTrace.php';
SqlTrace::log('users.list', $sql);
```

3) Report coverage:
```bash
pwsh ./scripts/quality/Coverage-Sql.ps1 -PackagesDir ./packages -TraceFile ./.sqltrace/exec.log -FailOnMiss
```
