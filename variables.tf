variable "cluster_name" {
  description = "Name of cluster"
  type        = string
  default     = ""
}

# variable "grafana_endpoint" {
#   description = "Grafana endpoint"
#   type        = string
#   default     = null
# }

# variable "grafana_api_key" {
#   description = "API key for authorizing the Grafana provider to make changes to Amazon Managed Grafana"
#   type        = string
#   sensitive   = true
# }