variable "kubeconfig" { type = string; description = "Path to kubeconfig" }
variable "namespace"  { type = string; default = "observability" }

variable "grafana_admin_user"     { type = string; default = "admin" }
variable "grafana_admin_password" { type = string; sensitive = true }
variable "grafana_url"            { type = string; description = "Grafana URL (http[s]://...)" }

variable "elasticsearch_enabled"  { type = bool; default = true }
