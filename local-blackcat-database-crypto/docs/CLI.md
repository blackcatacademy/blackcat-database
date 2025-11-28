# CLI Overview

| Command | Description |
| --- | --- |
| `bin/db-crypto-plan` | Validates `config/encryption.*` proti manifestu a volitelně proti schématu (`--schema=path` nebo `--dsn=...`). Exit code 2 značí varování. |
| `bin/db-crypto-schema` | Vytvoří snapshot ve formátu [docs/SCHEMA.md](./SCHEMA.md) přímo z databáze (`$DB_USER`/`$DB_PASSWORD` + DSN). |
