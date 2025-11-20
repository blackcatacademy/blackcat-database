#!/usr/bin/env bash
set -euo pipefail
DB_DSN="${1:-}"
DB_USER="${2:-}"
DB_PASS="${3:-}"
if [[ -z "$DB_DSN" ]]; then echo "Usage: PG-BackupRestore.sh <DSN> <USER> <PASS>"; exit 2; fi
host=$(echo "$DB_DSN" | sed -n 's/.*host=\([^;]*\).*/\1/p')
port=$(echo "$DB_DSN" | sed -n 's/.*port=\([^;]*\).*/\1/p')
db=$(echo "$DB_DSN" | sed -n 's/.*dbname=\([^;]*\).*/\1/p')
export PGPASSWORD="$DB_PASS"
pg_dump -h "$host" -p "${port:-5432}" -U "$DB_USER" -d "$db" -Fc -f backup.dump
createdb -h "$host" -p "${port:-5432}" -U "$DB_USER" "restore_smoke"
pg_restore -h "$host" -p "${port:-5432}" -U "$DB_USER" -d "restore_smoke" backup.dump
cnt=$(psql -h "$host" -p "${port:-5432}" -U "$DB_USER" -d restore_smoke -At -c "select count(*) from information_schema.tables where table_schema='public'")
echo "TABLES=$cnt"
test "$cnt" -gt 0
dropdb -h "$host" -p "${port:-5432}" -U "$DB_USER" restore_smoke
