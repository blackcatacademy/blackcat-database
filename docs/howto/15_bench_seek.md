# How-to: Bench presets & keyset seek

## Quick start
```bash
# Quick smoke (2 threads, 10s)
pwsh ../blackcat-monitoring/bench/Run-Bench.ps1 -Dsn "$env:DB_DSN" -User "$env:DB_USER" -Pass "$env:DB_PASS" -Mode select -Concurrency 2 -Duration 10 -OutDir ../blackcat-monitoring/bench/results
```

## Keyset seek preset
- Uses `(created_at, id)` composite index (DESC) and **keyset pagination**:
  ```sql
  WHERE (created_at < :ts) OR (created_at = :ts AND id < :id)
  ORDER BY created_at DESC, id DESC
  LIMIT :page
  ```
- Start cursor = most recent row; when the page underflows (no rows), it wraps to latest again.

Run:
```bash
pwsh ../blackcat-monitoring/bench/Run-Bench.ps1 -Dsn "$env:DB_DSN" -User "$env:DB_USER" -Pass "$env:DB_PASS" -Mode seek -Concurrency 8 -Duration 60 -OutDir ../blackcat-monitoring/bench/results
```

## Data generator
- If table is missing or has fewer rows than `-SeedRows` (default `50k`), it seeds rows with randomized `created_at` timestamps and unique `title`.
- Table definition:
  - `id BIGSERIAL/AUTO_INCREMENT` PK
  - `created_at` timestamptz/timestamp, default now
  - `title` unique (PG: `TEXT`; MySQL/MariaDB: `VARCHAR(255)`)
  - `deleted_at` nullable
  - indexes: `idx_<table>_created_id` on `(created_at DESC, id DESC)`

## Outputs
- Each worker writes a CSV `bench/results/worker_N.csv` with columns: `iter,ms,ok,rows`.
- Use plotting script:
  ```bash
  python3 ../blackcat-monitoring/bench/Bench-Plot.py --glob "../blackcat-monitoring/bench/results/*.csv" --outdir ../blackcat-monitoring/bench/plots
  ```
