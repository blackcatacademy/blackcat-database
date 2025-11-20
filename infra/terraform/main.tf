provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = "${var.grafana_admin_user}:${var.grafana_admin_password}"
}

resource "kubernetes_namespace" "obs" {
  metadata { name = var.namespace }
}

module "loki" {
  source    = "./modules/loki"
  namespace = kubernetes_namespace.obs.metadata[0].name
}

module "grafana" {
  source                 = "./modules/grafana"
  namespace              = kubernetes_namespace.obs.metadata[0].name
  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password
}

module "elasticsearch" {
  count     = var.elasticsearch_enabled ? 1 : 0
  source    = "./modules/elasticsearch"
  namespace = kubernetes_namespace.obs.metadata[0].name
}

# Datasources in Grafana (point to in-cluster services)
resource "grafana_data_source" "loki" {
  name = "Loki"
  type = "loki"
  url  = "http://loki-stack:3100"
  json_data = jsonencode({
    maxLines = 1000
  })
}

resource "grafana_data_source" "elastic" {
  count = var.elasticsearch_enabled ? 1 : 0
  name  = "Elasticsearch"
  type  = "elasticsearch"
  url   = "http://elasticsearch-master:9200"
  json_data = jsonencode({
    index    = "bench-logs"
    timeField = "ts_iso"
  })
}

# Import bench dashboard
resource "grafana_dashboard" "bench" {
  config_json = file("${path.module}/../../grafana_blackcat_bench.json")
  overwrite   = true
  depends_on  = [grafana_data_source.loki]
}

output "namespace" { value = var.namespace }
