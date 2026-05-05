variable "aws_region" {
  type        = string
  description = "AWS region (same as EKS and state bucket)."
}

variable "github_repository" {
  type        = string
  description = "GitHub repository short name (e.g. kubernetes-mono-app)."
}

variable "state_bucket" {
  type        = string
  description = "Terraform state S3 bucket."
}

variable "state_region" {
  type        = string
  description = "Region of the state bucket."
}

variable "lock_table" {
  type        = string
  description = "DynamoDB Terraform lock table."
}

variable "foundation_state_key" {
  type        = string
  description = "S3 object key for foundation terraform.tfstate. Required when enable_eks_integration is true; ignored otherwise."
  default     = ""
}

variable "enable_eks_integration" {
  type        = bool
  description = "When true, read foundation remote state, grant Lambda EKS API access, and allow cluster-mode deploys. When false, only static/parked S3 + CloudFront paths work (no live cluster required)."
  default     = true
}

variable "parked_site_state_key" {
  type        = string
  description = "S3 object key for parked_site terraform.tfstate."
}

variable "site_mode_parameter_name" {
  type        = string
  description = "SSM String parameter for active stack (cluster | static)."
  default     = "/kubernetes-mono-app/site_mode"
}
