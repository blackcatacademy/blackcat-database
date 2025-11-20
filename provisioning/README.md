# provisioning

Artifacts that bootstrap third-party tools such as Grafana once the underlying
infrastructure is up.

- `grafana/dashboards/bench.json` – canonical bench dashboard definition used by
  Terraform Helm releases and manual Grafana imports alike.

Keep additional provisioning payloads (datasource JSON, alert rules, etc.) under
this tree so they can be shared between automation paths (Terraform, kubectl,
manual import).
