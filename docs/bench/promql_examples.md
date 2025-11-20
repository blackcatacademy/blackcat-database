# PromQL Examples for Bench Metrics

**All metrics carry labels**: `app="blackcat-bench", db, mode, table`.

## Requests per second
```promql
sum(rate(bench_ops_total{app="blackcat-bench"}[1m]))
```

## Error rate (%)
```promql
100 * (sum(rate(bench_errors_total{app="blackcat-bench"}[5m])))
    / clamp_min(sum(rate(bench_ops_total{app="blackcat-bench"}[5m])), 1)
```

## Latency (avg over 5m)
```promql
sum(rate(bench_latency_ms_sum{app="blackcat-bench"}[5m]))
/
clamp_min(sum(rate(bench_latency_ms_count{app="blackcat-bench"}[5m])), 1)
```

## Latency p95 over 5m
> Uses histogram_quantile() over `bench_latency_ms_bucket` (ms).
```promql
histogram_quantile(
  0.95,
  sum by (le) (rate(bench_latency_ms_bucket{app="blackcat-bench"}[5m]))
)
```

## Latency p99 over 5m
```promql
histogram_quantile(
  0.99,
  sum by (le) (rate(bench_latency_ms_bucket{app="blackcat-bench"}[5m]))
)
```

## Rows per second
```promql
sum(rate(bench_rows_total{app="blackcat-bench"}[1m]))
```

## Split by DB dialect
```promql
sum by (db)(rate(bench_ops_total{app="blackcat-bench"}[1m]))
```
