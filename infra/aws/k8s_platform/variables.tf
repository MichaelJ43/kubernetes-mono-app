variable "aws_region" {
  type = string
}

variable "state_bucket" {
  type = string
}

variable "state_region" {
  type = string
}

variable "lock_table" {
  type = string
}

variable "foundation_state_key" {
  type        = string
  description = "S3 key for foundation terraform.tfstate"
}

variable "external_dns_route53_zone_id" {
  type        = string
  default     = null
  nullable    = true
  description = <<-EOT
    Public Route 53 hosted zone ID for the Kubernetes DNS zone (e.g. the zone for k8s.example.dev).
    When set, installs ExternalDNS (Helm) with IRSA so Ingress hostnames (e.g. api.k8s.example.dev)
    get alias records to the AWS load balancer after Argo syncs the Ingress. Use the zone that holds
    ACM validation records for that zone.
  EOT
}
