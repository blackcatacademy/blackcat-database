# blackcat-database-crypto – Roadmap

## Stage 1 – Adaptive Encryptor (current)
- [x] Konfigurovatelná mapa tabulek/sloupců (JSON/YAML nebo PHP array).
- [x] `DatabaseCryptoAdapter` (encrypt + HMAC) delegující na libovolný gateway.
- [x] Referenční `PdoGateway` + unit testy pro `PayloadEncryptor`.
- [x] Manifest napojení (`BLACKCAT_CRYPTO_MANIFEST`) → shoda se zbytkem platformy.

## Stage 2 – Schema-Aware Diagnostics
- CLI `db-crypto:plan` validuje mapu oproti manifestu (`blackcat-crypto-manifests`) a umí načíst snapshot nebo přímé DB schema (`--schema` / `--dsn`) – hlásí chybějící/přebytečné sloupce.
- `db-crypto-schema` generuje snapshoty přímo z databáze pro version-control / CI.
- Linter pro PR (GitHub Action) – JSON schema + phpunit test pro mapu.
- Možnost označit sloupce jako `deterministic` (AEAD vs HMAC) podle potřeby indexů.

## Stage 3 – Transparent Query Hooks
- Middleware pro `blackcat-database` repositories (automatické zapojení do `BulkUpsertRepository`, `ContractRepository`).
- Eventy `beforeInsert`/`beforeUpdate` obohacené o `encryption_context` pro observabilitu.
- Podpora `decrypt()` helperů (např. pro audit logy, download endpoints).

## Stage 4 – Tokenization & Search
- Deterministické tokeny pro LIKE/ILIKE vyhledávání (kombinace HMAC + prefix tables).
- Bloom filter indexy pro anonymní vyhledávání.
- Pre/post hooks pro `blackcat-search` modul (automatické odmaskování při indexaci).

## Stage 5 – Runtime Governance
- Telemetrie (Prometheus) – počty zašifrovaných polí, chyby, vynechané mapy.
- Policy enforcement (napojení na `blackcat-governance`): „co se musí šifrovat“ vs. realita.
- CLI `db-crypto:enforce` – reencrypt existující data podle nové politiky (spolupráce s `vault:migrate`).

## Stage 6 – Multi-language SDK
- TypeScript + Go light-weight klienti sdílející stejnou mapu (`blackcat-crypto-manifests`).
- Declarativní kódgen (json-schema -> PHP trait pro repositories, TS decorators, etc.).

## Stage 7 – Secret-Aware Backups
- Adapter pro `blackcat-backup` – exportuje envelopes + manifest metainformace.
- Automatic wrap queue scheduling při obnově backupu (zajistí rewrap u odhalených klíčů).

## Stage 8 – Zero Trust DB Mesh
- Federované DB nody sdílející pouze encrypted payloady + policy handshake.
- Dynamic context negotiation (per tenant) – auto mapy podle `tenant.region` / `compliance profile`.
- Self-service CLI/portal pro security tým (audit, revoke, rewrap, compliance reporty).

## Stage 9 – Autonomous Observability
- Streaming audit feed do `blackcat-observability` (detekce ne-/zašifrovaných zápisů v reálném čase).
- Prometheus dashboard „encryption coverage“ + vzorkování plaintextů (bez hodnot, pouze meta).
- Hook do `blackcat-feedback` pro dev UX telemetry (kolik času ušetří automatické šifrování).

## Stage 10 – Intelligent Deidentification
- Strojové učení nad mapou (auto doporučení kontextů na základě datového profilu).
- Integrace s `blackcat-ai` pro generování anonymizovaných datasetů bez manuální konfigurace.
- „What-if“ simulátor – CLI `db-crypto:simulate anonymization` (počítá dopad na dotazy/indexy).

## Stage 11 – Runtime Policy Orchestrator
- Napojení na `blackcat-orchestrator` – při změně politiky se vyžádá rewrap/rehash, spustí se pipeline do `blackcat-crypto`.
- Webhooky do `blackcat-governance` pro approvals (např. povolení dočasného plaintext přístupu).
- Drift detection: porovná skutečnou DB (pg_dump) vs. mapu → auto ticket v `blackcat-support`.

## Stage 12 – Developer Delight / SDK Everywhere
- Jednotné SDK moduly (PHP, TS, Go, Rust) s generovanými typy + IDE helpers.
- VS Code / PHPStorm plugin: zvýrazní místa, kde chybí šifrovací strategie.
- `db-crypto playground` (web app) – prototypování mapy na sample datech, generování migration skriptů.
