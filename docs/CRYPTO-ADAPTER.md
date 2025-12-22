# Database Crypto Adapter

For automatic input encryption you can use [`blackcat-database-crypto`](../blackcat-database-crypto). It bridges `blackcat-crypto` (manifests + `CryptoManager`) with the `blackcat-database` write path (repositories / services / CLI actions) and ensures sensitive columns are automatically encrypted or HMAC'd before writing.

## How it works
1. In runtime config (`blackcat-config`) define crypto slots/contexts (recommended: `crypto.manifest`).
2. Define per-package encryption maps in `packages/*/schema/encryption-map.json` (single source of truth).
3. Enable the ingress adapter (zero boilerplate) via `IngressLocator` and use standard repos/services:

```php
use BlackCat\Core\Database;
use BlackCat\Database\Packages\Users\Repository\UserRepository;
use BlackCat\Database\Services\GenericCrudService;
use BlackCat\Database\Crypto\IngressLocator;

// 1) Standard boot (DB) + env configuration:
// - runtime config: crypto.keys_dir=/path/to/keys, crypto.manifest=/path/to/contexts/core.json

// 2) IngressLocator boots itself from packages + keys (hardcoded map source)
// (GenericCrudService uses it automatically)
IngressLocator::requireAdapter(); // fail-fast

$db = Database::getInstance();
$repo = new UserRepository($db);
$svc  = new GenericCrudService($db, $repo, 'id');

// The write path is automatically encrypted/HMAC'd according to the map (no raw PDO, no manual encrypt() calls).
$svc->create(['id' => 1, 'ssn' => '...']);
```

## Deterministic lookup (login/search)

For queries like “find a user by email”, store the lookup column deterministically as `hmac` (e.g. `users.email_hash`).
Then your application code never computes HMACs manually:

```php
// 1) Repo can apply the deterministic transform automatically (HMAC-only) before WHERE:
$user = $repo->getByUnique(['email_hash' => $email]);

// 2) Or via the service:
$exists = $svc->existsByKeys(['email_hash' => $email]);
```

Note: the deterministic transform is intentionally HMAC-only; `encrypt` (non-deterministic) is rejected for criteria to avoid false queries.

## How to integrate
- **CLI / Migrations** – centralized in `blackcat-cli` (optional): `blackcat db-crypto plan|schema|telemetry|keys-sync`.
- **Repositories** – repos support an ingress hook (`setIngressAdapter()`), but are typically wired automatically via `IngressLocator` (zero boilerplate). `GenericCrudService` also propagates the adapter into the repo instance.
- **Observability** – adapter telemetry (number of encrypted fields, errors) can be integrated with `blackcat-observability` alongside DB metrics.

The current roadmap (Stage 1–12) is available in `blackcat-database-crypto/docs/ROADMAP.md`.
