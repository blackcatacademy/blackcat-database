# BlackCat Database Crypto Adapter

Automatický šifrovací/obfuskační adapter pro `blackcat-database`. Cílem je, aby aplikační kód pouze předal vstupní payload a adapter sám:

1. Podle manifestu najde sloupce/sloty vyžadující šifrování nebo HMAC.
2. Využije `blackcat-crypto` (`CryptoManager`) pro vytvoření envelope nebo značky.
3. Deleguje výsledek na původní `blackcat-database` gateway (PDO, repository, action).

Tím pádem se „vstup → šifrování → databáze“ zkrátí na jediný krok.

## Rychlý start

```bash
composer install

export BLACKCAT_CRYPTO_MANIFEST=../blackcat-crypto-manifests/contexts/core.json
php example.php   # viz examples/
# validace mapy (snapshot)
php bin/db-crypto-plan --schema=config/schema.snapshot.json config/encryption.example.json
# nebo přímo proti živé DB (použije $DB_USER / $DB_PASSWORD)
DB_USER=root DB_PASSWORD=secret php bin/db-crypto-plan --dsn=\"mysql:host=127.0.0.1;dbname=blackcat\" config/encryption.example.json
# export schématu pro CI
DB_USER=root DB_PASSWORD=secret php bin/db-crypto-schema \"mysql:host=127.0.0.1;dbname=blackcat\" config/schema.snapshot.json
```

### Konfigurace šifrovaných polí

`config/encryption.example.json` obsahuje mapu tabulek/sloupců:

```json
{
  "tables": {
    "users": {
      "columns": {
        "ssn": {"strategy": "encrypt", "context": "core.vault"},
        "email_hash": {"strategy": "hmac", "context": "core.hmac.email"}
      }
    }
  }
}
```

Nahraj vlastní JSON / PHP pole, načti přes `EncryptionMap::fromFile()` a předej do `DatabaseCryptoAdapter`.

## API

```php
use BlackCat\Crypto\Config\CryptoConfig;
use BlackCat\Crypto\CryptoManager;
use BlackCat\DatabaseCrypto\Config\EncryptionMap;
use BlackCat\DatabaseCrypto\Adapter\DatabaseCryptoAdapter;
use BlackCat\DatabaseCrypto\Gateway\PdoGateway;

$crypto = CryptoManager::boot(CryptoConfig::fromEnv());
$map = EncryptionMap::fromFile(__DIR__ . '/config/encryption.json');
$gateway = new PdoGateway($pdo);
$adapter = new DatabaseCryptoAdapter($crypto, $map, $gateway);

$adapter->insert('users', [
    'id' => 1,
    'ssn' => '123-45-6789',
    'email_hash' => 'alice@example.com'
]);
```

Adapter vrátí výsledek původního gatewaye (např. `PDOStatement`, bool atd.).

### Možnosti strategií
-
- `encrypt` – použije `CryptoManager::encryptContext()` a uloží envelope (Base64).
- `hmac` – použije `CryptoManager::hmac()` a uloží podpis (hex/base64 podle nastavení).
- `passthrough` – ponechá hodnotu beze změny (užitečné při kombinovaných mapách).

### Schema snapshots

Pro volitelnou kontrolu proti živému schématu připrav JSON dle [docs/SCHEMA.md](./docs/SCHEMA.md). `db-crypto-plan` pak zvýrazní sloupce, které v DB chybí, a v CI vrátí nenulový exit kód.

## CLI / Integrace

Brzy přibude CLI `db-crypto:dry-run` pro validaci mapy proti živé schémě (ROADMAP Stage 2). Zatím je k dispozici pouze PHP API.

## Licence
Proprietární / BlackCat Academy.
