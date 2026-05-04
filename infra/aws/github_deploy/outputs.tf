output "github_actions_terraform_role_arn" {
  description = "Use for GitHub Actions secret AWS_DEPLOY_ROLE_ARN (Terraform + cluster workflows)."
  value       = aws_iam_role.github_terraform.arn
}

output "github_actions_bootstrap_role_arn" {
  description = "Optional narrow GitOps-only role."
  value       = aws_iam_role.github_bootstrap.arn
}

output "github_actions_oidc_provider_arn" {
  value = local.github_actions_oidc_provider_arn
}
