data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# GitHub Actions IAM roles are created by the separate **github_deploy** root module.
# Resolve them by **name** (same convention as **github_deploy**) so **foundation** plan/destroy
# does not depend on **github_deploy** Terraform state existing in S3 (e.g. state object removed
# while IAM roles remain).
data "aws_iam_role" "github_terraform" {
  name = "${var.cluster_name}-gha-terraform"
}

data "aws_iam_role" "github_bootstrap" {
  name = "${var.cluster_name}-gha-bootstrap"
}
