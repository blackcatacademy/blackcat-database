# Bench tooling moved

Bench and performance tooling (workers, plots, Prometheus exporter, upload helpers) was moved to:

- `blackcat-monitoring/bench`

This keeps `blackcat-database` focused on database/runtime logic while monitoring/observability assets live in the dedicated ops repo.

