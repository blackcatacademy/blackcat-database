#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${PHPUNIT_DOCKER_IMAGE:-blackcat-db-php-pcov}"

# Build the image (includes pcov from Dockerfile.php) if it is missing
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -f "$ROOT/Dockerfile.php" -t "$IMAGE" "$ROOT"
fi

docker run --rm --network=host \
  -v "$ROOT":/app -w /app \
  -e BC_DB="${BC_DB:-}" \
  -e MYSQL_DSN -e MYSQL_USER -e MYSQL_PASS \
  -e MARIADB_DSN -e MARIADB_USER -e MARIADB_PASS \
  -e PG_DSN -e PG_USER -e PG_PASS \
  "$IMAGE" vendor/bin/phpunit -c tests/phpunit.xml.dist "$@"

