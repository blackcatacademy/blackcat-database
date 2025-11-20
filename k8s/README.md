# k8s

Raw Kubernetes manifests that compliment the Terraform stack or can be applied
manually when you only need specific components.

- `manifests/grafana-provisioning.yaml` – ConfigMaps with Grafana datasources
  and the bench dashboard JSON.
- `manifests/prometheus-rules.yml` – PrometheusRule CRD containing bench SLO
  alerts ready for kube-prometheus-stack.

Apply with `kubectl apply -f k8s/manifests/` once the cluster has the required
CRDs (e.g. Prometheus operator) and namespaces.
