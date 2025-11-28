# Schema Snapshot Format

`bin/db-crypto-plan` umí kromě manifestu porovnat mapu i se skutečným schématem. Kvůli jednoduchosti přijímá JSON:

```json
{
  "tables": {
    "users": ["id", "email", "ssn"],
    "orders": ["id", "card_pan", "card_pan_last4"]
  }
}
```

Stačí vypsat tabulky/sloupce, které existují (např. z `information_schema` nebo `blackcat-database` generovaných definic). CLI pak upozorní na všechny šifrované sloupce, které v DB nejsou, a vrátí exit code `2` pro snadnou integraci do CI.
