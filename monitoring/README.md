# monitoring

Alerting profiles and Alertmanager configuration that can be consumed by a
Prometheus/Alertmanager stack without the Terraform/Kubernetes layers.

- `bench_alerts.yml` – vanilla Prometheus rule file for bench SLOs (error rate,
  p95 latency, and traffic heartbeat).
- `alertmanager.yml` – reference configuration that routes alerts to Slack
  channels or the data-team mailbox with sane grouping defaults.

Mount or copy these files into your observability stack to share the same alert
semantics between environments.
