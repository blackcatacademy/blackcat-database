# Terraform — Observability Stack (Loki + Grafana + Elasticsearch)

This Terraform deploys observability components into a Kubernetes cluster via Helm and wires **Grafana datasources** and the **bench dashboard**.

## Prerequisites
- Kubernetes cluster + kubeconfig
- Terraform 1.5+
- Grafana reachable at `var.grafana_url` with admin credentials (can be the Grafana installed by this stack if you expose it).

## Usage
```bash
cd infra/terraform
export TF_VAR_kubeconfig=~/.kube/config
export TF_VAR_grafana_admin_password='adminpass'
export TF_VAR_grafana_url='http://grafana.observability.svc:3000'  # or Ingress/NodePort URL

terraform init
terraform apply -auto-approve
```

After apply:
- Loki available as `loki-stack` service (port 3100) in the `observability` namespace.
- Grafana deployed; add an Ingress/NodePort to access it externally if needed.
- Grafana datasources created (Loki + optional Elasticsearch).
- Bench dashboard imported (`grafana_blackcat_bench.json`).

## Notes
- To disable Elasticsearch, set `-var='elasticsearch_enabled=false'`.
- If Grafana is the one installed here, set up a Service/Ingress and use that URL in `grafana_url` (provider requires an accessible HTTP endpoint).
