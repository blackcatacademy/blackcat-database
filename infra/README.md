# infra

Infrastructure-as-code assets that complement the database layer.

- `terraform/` – complete observability stack (Loki + Grafana + optional
  Elasticsearch) provisioned via Helm with pre-wired datasources and the bench
  dashboard. See `terraform/README.md` for requirements and usage.

Additional infrastructure modules can live alongside the Terraform stack. Keep
the directory focused on provisioning cloud/platform resources.
