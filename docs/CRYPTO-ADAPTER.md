# Database Crypto Adapter

Pro automatické šifrování vstupů můžeš využít balíček [`blackcat-database-crypto`](../blackcat-database-crypto). Ten propojí `blackcat-crypto` (manifesty + `CryptoManager`) s libovolným gateway (`PDO`, repository, CLI akce) a zajistí, že citlivé sloupce se před zápisem samy zašifrují nebo podepíší.

## Princip
1. V `BLACKCAT_CRYPTO_MANIFEST` definuj všechny kontexty/sloupce.
2. Vytvoř mapu (`config/encryption.json`), která řekne, jaké strategie (`encrypt`/`hmac`/`passthrough`) mají být použity na konkrétní tabulky.
3. Obal svůj gateway / repository pomocí `DatabaseCryptoAdapter`:

```php
use BlackCat\Crypto\Config\CryptoConfig;
use BlackCat\Crypto\CryptoManager;
use BlackCat\Database\Crypto\Config\EncryptionMap;
use BlackCat\Database\Crypto\Gateway\PdoGateway;
use BlackCat\Database\Crypto\Adapter\DatabaseCryptoAdapter;

$crypto = CryptoManager::boot(CryptoConfig::fromEnv());
$map = EncryptionMap::fromFile(__DIR__ . '/../config/encryption.json');
$gateway = new PdoGateway($pdo);
$adapter = new DatabaseCryptoAdapter($crypto, $map, $gateway);

$adapter->insert('users', ['id' => 1, 'ssn' => '...']);
```

## Kem integruj
- **CLI / Migrations** – wrapper můžeš použít i v `bin/database` příkazech, takže se ani seed data už neskládají v plaintextu.
- **Repositories** – implementuj `DatabaseGatewayInterface` pro své repozitáře, nebo využij plánovaný middleware v `blackcat-database-crypto` Stage 3.
- **Observabilita** – telemetrie z adapteru (počet zašifrovaných polí, chyby) můžeš napojit na `blackcat-observability` společně s DB metrikami.

Aktuální roadmapa (Stage 1–12) je k dispozici v `blackcat-database-crypto/docs/ROADMAP.md`.
