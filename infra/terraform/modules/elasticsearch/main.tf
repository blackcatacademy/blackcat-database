variable "namespace" { type = string }

resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  namespace  = var.namespace
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "elasticsearch"
  version    = "19.6.7"

  values = [yamlencode({
    master = {
      replicaCount = 1
      persistence = { enabled = false }
    }
    data = {
      replicaCount = 0
    }
    coordinating = {
      replicaCount = 0
    }
    ingest = {
      replicaCount = 0
    }
    volumePermissions = { enabled = true }
    global = { kibanaEnabled = false }
  })]
}
