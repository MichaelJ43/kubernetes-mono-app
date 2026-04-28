variable "aws_region" {
  type        = string
  description = "Region for EKS and supporting resources."
}

variable "cluster_name" {
  type        = string
  default     = "k8s-mono"
  description = "EKS cluster name (must match kubeconfig / GitHub workflow inputs)."
}

variable "cluster_version" {
  type        = string
  default     = "1.29"
  description = "EKS control plane version."
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  type        = bool
  default     = false
  description = "If false, nodes use public subnets only (lower cost; portfolio-only)."
}

variable "github_organization" {
  type        = string
  description = "GitHub org or user (e.g. MichaelJ43)."
}

variable "github_repository" {
  type        = string
  default     = "kubernetes-mono-app"
  description = "Repository name without org prefix."
}

variable "acm_certificate_domain" {
  type        = string
  default     = null
  nullable    = true
  description = <<-EOT
    Optional. Primary domain name of an ISSUED ACM certificate in var.aws_region (same region as ALB).
    Example: "*.k8s.example.dev" or "api.k8s.example.dev". Must match the name shown in ACM.
    When set, Terraform exposes output acm_certificate_arn (optional reference only; default Ingress does not need ARN in Git).
  EOT
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}
