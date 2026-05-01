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
  default     = "1.30"
  description = <<-EOT
    EKS control plane version. AWS allows only **one minor version upgrade at a time**
    (e.g. 1.29 → 1.30, then 1.30 → 1.31 in a later apply). Greenfield clusters can use
    the latest default; upgrading an existing cluster may require stepping this value.
  EOT
}

variable "create_github_oidc_provider" {
  type        = bool
  default     = false
  description = <<-EOT
    If true, Terraform creates the IAM OIDC provider for https://token.actions.githubusercontent.com.
    AWS allows only one per account. Set true on the first apply in a new account that has no GitHub OIDC provider yet.
    If you already use GitHub Actions OIDC in this account (common), leave false so Terraform reuses the existing provider.
  EOT
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

variable "github_actions_deploy_role_arn" {
  type        = string
  default     = null
  nullable    = true
  description = <<-EOT
    When GitHub Actions assumes a deploy IAM role that is not the foundation-managed
    github_terraform role, set this to the same ARN as AWS_DEPLOY_ROLE_ARN so EKS grants
    that principal Kubernetes API access (helm in k8s_platform). Workflows pass this
    automatically from the secret. Omit or leave null when running locally with the
    github_terraform role only.
  EOT
}

variable "acm_certificate_domain" {
  type        = string
  default     = null
  nullable    = true
  description = <<-EOT
    Optional. Primary domain name of an ISSUED ACM certificate in var.aws_region (same region as ALB).
    Example: "*.k8s.example.dev" or "api.k8s.example.dev". Must match the name shown in ACM.
    Ignored when acm_certificate_arn is set.
    Exposes output acm_certificate_arn (optional reference; default Ingress uses discovery without ARN in Git).
  EOT
}

variable "acm_certificate_arn" {
  type        = string
  default     = null
  nullable    = true
  description = <<-EOT
    Optional. Full ARN of an ISSUED ACM certificate in var.aws_region (same as ALB).
    When set (e.g. TF_ACM_CERTIFICATE_ARN in GitHub Actions), takes precedence over acm_certificate_domain
    for output acm_certificate_arn. Does not modify Kubernetes manifests; Ingress still uses discovery unless you overlay an annotation.
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
