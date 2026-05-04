variable "aws_region" {
  type        = string
  description = "AWS region (IAM is global; used for provider and tagging only)."
  default     = "us-east-1"
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

variable "cluster_name" {
  type        = string
  default     = "k8s-mono"
  description = "Prefix for IAM role names; must match foundation cluster_name."
}

variable "create_github_oidc_provider" {
  type        = bool
  default     = false
  description = <<-EOT
    If true, Terraform creates the IAM OIDC provider for https://token.actions.githubusercontent.com.
    AWS allows only one per account. Set true on a greenfield account.
  EOT
}
