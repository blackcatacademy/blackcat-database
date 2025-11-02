
`docs/generators.md`
```md
# Generators

- Split-SchemaToPackages.ps1 → writes `schema/001/020/030` to each package
- New-PackageReadmes.ps1     → README per package
- Build-Definitions.ps1      → docs/definition.md (columns metadata)
- New-PackageChangelogs.ps1  → CHANGELOG.md per package
- New-DocsIndex.ps1          → root PACKAGES.md

Run order (umbrella root):
```bash
pwsh ./scripts/mk-schema.ps1 -SeedInTransaction -Force
pwsh ./scripts/Cleanup-SchemaFolders.ps1 -WhatIf pwsh ./scripts/Cleanup-SchemaFolders.ps1

pwsh ./scripts/Split-SchemaToPackages.ps1 -PackagesDir ./packages
pwsh ./scripts/New-PackageReadmes.ps1      -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -Force
pwsh ./scripts/Build-Definitions.ps1       -MapPath ./scripts/schema-map.psd1 -DefsPath ./scripts/schema-defs.psd1 -PackagesDir ./packages -Force
pwsh ./scripts/New-PackageChangelogs.ps1   -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -Force
pwsh ./scripts/New-DocsIndex.ps1           -MapPath ./scripts/schema-map.psd1 -PackagesDir ./packages -OutPath ./PACKAGES.md -Force

pwsh -NoProfile -File ./scripts/Generate-PhpFromSchema.ps1 `
  -TemplatesRoot ./scripts/templates/php `
  -ModulesRoot   ./packages `
  -SchemaDir     ./scripts/schema `
  -EnginePreference auto `
  -StrictSubmodules `
  -WhatIf `
  -Verbose
pwsh -NoProfile -File ./scripts/Generate-PhpFromSchema.ps1 `
  -TemplatesRoot ./scripts/templates/php `
  -ModulesRoot   ./packages `
  -SchemaDir     ./scripts/schema `
  -EnginePreference auto `
  -StrictSubmodules `
  -Verbose -Force

docker compose run --rm -e BC_DB=mysql app php ./tests/ci/run.php  
docker compose run --rm -e BC_DB=postgres app php ./tests/ci/run.php

docker compose exec -T mysql mysql -uroot -proot -e "DROP DATABASE IF EXISTS test; CREATE DATABASE test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
docker compose exec -T postgres psql -U postgres -d test -v ON_ERROR_STOP=1 -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres; GRANT ALL ON SCHEMA public TO public;"

docker compose run --rm -e BC_DB=mysql -e MYSQL_DSN="mysql:host=mysql;port=3306;dbname=test;charset=utf8mb4" -e MYSQL_USER=root -e MYSQL_PASS=root app ./vendor/bin/phpunit -c tests/phpunit.xml.dist --testsuite "DB Integration"

docker compose run --rm -e BC_DB=postgres -e PG_DSN="pgsql:host=postgres;port=5432;dbname=test" -e PG_USER=postgres -e PG_PASS=postgres app ./vendor/bin/phpunit -c tests/phpunit.xml.dist --testsuite "DB Integration"

docker compose run --rm -e BC_DB=mysql -e MYSQL_DSN="mysql:host=mysql;port=3306;dbname=test;charset=utf8mb4" -e MYSQL_USER=root -e MYSQL_PASS=root -e BC_STRESS=1 app ./vendor/bin/phpunit -c tests/phpunit.xml.dist --testsuite "DB Integration"

docker compose build --no-cache app
docker compose run --rm app composer update
docker compose run --rm app composer dump-autoload -o

docker compose run --rm -e BC_DB=mysql app php ./tests/ci/run.php
docker compose run --rm -e BC_DB=postgres app php ./tests/ci/run.php

docker compose run --rm -e BC_DB=mysql -e MYSQL_DSN="mysql:host=mysql;port=3306;dbname=test;charset=utf8mb4" -e MYSQL_USER=root -e MYSQL_PASS=root -e BC_INSTALLER_DEBUG=1 -e BC_DEBUG=1 -e BC_TRACE_VIEWS=1 -e BC_STRESS=1 -e BC_INSTALLER_TRACE_FILES=1 -e BC_NO_CACHE=1 -e BC_INSTALLER_TRACE_SQL=1 -e BC_HARNESS_STRICT_VIEWS=1 -e BC_ORDER_GUARD=1 app ./vendor/bin/phpunit -c tests/phpunit.xml.dist --testsuite "DB Integration" *> .\logs\db-integration.log

docker compose run --rm -e BC_DB=postgres -e PG_DSN="pgsql:host=127.0.0.1;port=5432;dbname=test;options='-c client_encoding=UTF8'" -e PG_USER=postgres -e PG_PASS=postgres -e BC_INSTALLER_DEBUG=1 -e BC_DEBUG=1 -e BC_TRACE_VIEWS=1 -e BC_STRESS=1 -e BC_INSTALLER_TRACE_FILES=1 -e BC_NO_CACHE=1 -e BC_INSTALLER_TRACE_SQL=1 -e BC_HARNESS_STRICT_VIEWS=1 -e BC_ORDER_GUARD=1 app ./vendor/bin/phpunit -c tests/phpunit.xml.dist --testsuite "DB Integration" *> .\logs\db-integration.log