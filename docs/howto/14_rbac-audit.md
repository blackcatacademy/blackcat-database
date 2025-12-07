# How-to: RBAC & Auditing

- Use roles `app_reader` (SELECT) and `app_writer` (DML).  
- Generate grants per table:
```bash
pwsh ./scripts/schema-tools/Generate-Roles.ps1 -MapPath ./scripts/schema/schema-map-postgres.yaml -OutPath ./docs/RBAC.sql
```
- Attach **actor_id** to logs and propagate a `correlation_id`:
```php
// At request start
$ctx = ['actor_id' => $userId ?? 0, 'corr_id' => bin2hex(random_bytes(8))];
// Add as SQL comment if you support it or log via middleware
```
