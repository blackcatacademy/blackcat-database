# tools

Developer tooling and automation helpers that are not part of the production
runtime.

- `scaffold.php` – all-in-one generator for modules, repositories, services,
  DTOs, migrations, views, epic test suites, and supporting helpers (audit
  trail, tenant scope, replica router, demo data, how-to docs). Run
  `php tools/scaffold.php <command> <Name>` for details.

Additional helper scripts (code mods, generators, analyzers) belong here so the
project has a single toolbox location.
