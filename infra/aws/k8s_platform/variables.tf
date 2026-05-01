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
    When set, installs ExternalDNS (Helm) with IRSA for other Ingresses, and creates Terraform-managed
    A/AAAA alias records for api.<zone> once the AWS Load Balancer Controller has created the ALB
    (may require a second apply after the API Ingress is synced). Use the zone that holds ACM validation records.
  EOT
}

variable "api_ingress_namespace" {
  type        = string
  default     = "portfolio"
  description = "Namespace of the public API Ingress (must match deploy/base/api kustomization). Used to find the ALB via ingress.k8s.aws/stack."
}

variable "api_ingress_name" {
  type        = string
  default     = "api"
  description = "Name of the public API Ingress resource. Used with api_ingress_namespace for ALB tag ingress.k8s.aws/stack."
}
