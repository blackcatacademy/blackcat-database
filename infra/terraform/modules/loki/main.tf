variable "namespace" { type = string }

resource "helm_release" "loki" {
  name       = "loki-stack"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = "2.10.2"

  values = [yamlencode({
    grafana = { enabled = false }
    promtail = {
      enabled = true
      extraScrapeConfigs = ""
    }
    loki = {
      persistence = { enabled = false }
    }
  })]
}
