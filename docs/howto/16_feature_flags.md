# How-to: Feature flags in views

1) Create `flags` table (`docs/feature_flags.sql`).
2) Wrap view computations with CASE based on `flags.value`.
3) In PHP, use `FeatureFlags` helper to read/update flags with small TTL cache.

```sql
INSERT INTO flags(key, value) VALUES ('users.name_case','upper')
ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value;
```
