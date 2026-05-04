variable "aws_region" {
  type        = string
  description = "Region for the S3 bucket origin."
  default     = "us-east-1"
}

variable "github_repository" {
  type        = string
  default     = "kubernetes-mono-app"
  description = "Repo name for resource naming."
}

variable "parked_aliases" {
  type        = list(string)
  description = "Hostnames for the CloudFront distribution (e.g. k8s.example.dev, api.k8s.example.dev)."
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN in us-east-1 for HTTPS viewer (reuse TF_ACM_CERTIFICATE_ARN when cert is in us-east-1)."
}

variable "route53_zone_id" {
  type        = string
  default     = ""
  description = "Route 53 hosted zone ID for parked aliases (same zone as ExternalDNS for k8s zone)."
}

variable "manage_route53_records" {
  type        = bool
  default     = false
  description = "When true, create alias A/AAAA records to CloudFront (use two-phase apply during soft-destroy; see docs)."
}
