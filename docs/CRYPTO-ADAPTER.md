# Database Crypto Adapter

Pro automatické šifrování vstupů můžeš využít balíček [`blackcat-database-crypto`](../blackcat-database-crypto). Ten propojí `blackcat-crypto` (manifesty + `CryptoManager`) s `blackcat-database` write‑path (repositories / služby / CLI akce) a zajistí, že citlivé sloupce se před zápisem samy zašifrují nebo podepíší.

## Princip
1. V `BLACKCAT_CRYPTO_MANIFEST` definuj všechny kontexty/sloupce.
2. Vytvoř mapu (`config/encryption.json`), která řekne, jaké strategie (`encrypt`/`hmac`/`passthrough`) mají být použity na konkrétní tabulky.
3. Zapni ingress adapter (zero‑boilerplate) přes `IngressLocator` a používej standardní repos/services:

```php
use BlackCat\Core\Database;
use BlackCat\Database\Packages\Users\Repository\UserRepository;
use BlackCat\Database\Services\GenericCrudService;
use BlackCat\Database\Crypto\IngressLocator;

// 1) Standard boot (DB) + env konfigurace:
// - BLACKCAT_DB_ENCRYPTION_MAP=./config/encryption.json
// - BLACKCAT_KEYS_DIR=./keys
// - BLACKCAT_CRYPTO_MANIFEST=.../contexts/core.json
// - (doporučeno) BLACKCAT_DB_ENCRYPTION_REQUIRED=1  # fail-closed

// 2) IngressLocator se sám nabootuje podle env (pokud je map+keys k dispozici)
// (GenericCrudService ho použije automaticky)
IngressLocator::requireAdapter(); // fail-fast

$db = Database::getInstance();
$repo = new UserRepository($db);
$svc  = new GenericCrudService($db, $repo, 'id');

// Write‑path je automaticky šifrovaný/HMAC podle mapy (bez raw PDO, bez ručního volání encrypt()).
$svc->create(['id' => 1, 'ssn' => '...']);
```

## Deterministic lookup (login/search)

Pro dotazy typu „najdi uživatele podle e‑mailu“ ukládej lookup sloupec deterministicky jako `hmac` (např. `users.email_hash`).
Pak v aplikačním kódu nepíšeš žádné HMAC ručně:

```php
// 1) Repo umí deterministický transform automaticky (HMAC-only) před WHERE:
$user = $repo->getByUnique(['email_hash' => $email]);

// 2) Nebo přes službu:
$exists = $svc->existsByKeys(['email_hash' => $email]);
```

Pozn.: Deterministic transform je záměrně HMAC-only; `encrypt` (nedeterministické) se pro criteria odmítá, aby nedošlo k falešným dotazům.

## Kem integruj
- **CLI / Migrations** – použij `blackcat-database-crypto/bin/db-crypto-*` (plan/schema/telemetry/keys-sync) a piš do DB přes `blackcat-database` (installer/repositories).
- **Repositories** – repos umí ingress hook (`setIngressAdapter()`), ale typicky se napojí automaticky přes `IngressLocator` (zero‑boilerplate). `GenericCrudService` navíc adapter propíše do repo instance.
- **Observabilita** – telemetrie z adapteru (počet zašifrovaných polí, chyby) můžeš napojit na `blackcat-observability` společně s DB metrikami.

Aktuální roadmapa (Stage 1–12) je k dispozici v `blackcat-database-crypto/docs/ROADMAP.md`.
