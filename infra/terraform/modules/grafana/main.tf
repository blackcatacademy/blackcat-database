variable "namespace"              { type = string }
variable "grafana_admin_user"     { type = string }
variable "grafana_admin_password" { type = string }

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "7.3.7"

  values = [yamlencode({
    adminUser     = var.grafana_admin_user
    adminPassword = var.grafana_admin_password
    service = {
      type = "ClusterIP"
      port = 3000
    }
    persistence = { enabled = false }
  })]
}
