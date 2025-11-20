#!/usr/bin/env bash
set -euo pipefail
DB_DSN="${1:-}"
DB_USER="${2:-}"
DB_PASS="${3:-}"
if [[ -z "$DB_DSN" ]]; then echo "Usage: MySQL-BackupRestore.sh <DSN> <USER> <PASS>"; exit 2; fi
host=$(echo "$DB_DSN" | sed -n 's/.*host=\([^;]*\).*/\1/p')
port=$(echo "$DB_DSN" | sed -n 's/.*port=\([^;]*\).*/\1/p')
db=$(echo "$DB_DSN" | sed -n 's/.*dbname=\([^;]*\).*/\1/p')
mysqldump -h "$host" -P "${port:-3306}" -u "$DB_USER" -p"$DB_PASS" "$db" > backup.sql
mysql -h "$host" -P "${port:-3306}" -u "$DB_USER" -p"$DB_PASS" -e "DROP DATABASE IF EXISTS restore_smoke; CREATE DATABASE restore_smoke;"
mysql -h "$host" -P "${port:-3306}" -u "$DB_USER" -p"$DB_PASS" restore_smoke < backup.sql
cnt=$(mysql -h "$host" -P "${port:-3306}" -u "$DB_USER" -p"$DB_PASS" -N -e "select count(*) from information_schema.tables where table_schema='restore_smoke'")
echo "TABLES=$cnt"
test "$cnt" -gt 0
mysql -h "$host" -P "${port:-3306}" -u "$DB_USER" -p"$DB_PASS" -e "DROP DATABASE restore_smoke"
