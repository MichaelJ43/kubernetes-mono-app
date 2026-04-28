output "cluster_name" {
  description = "Pass to Argo bootstrap workflow: cluster_name."
  value       = module.eks.cluster_name
}

output "aws_region" {
  description = "AWS region."
  value       = var.aws_region
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Configure local kubectl against this cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "github_actions_terraform_role_arn" {
  description = "GitHub Actions secret AWS_ROLE_ARN_TERRAFORM"
  value       = aws_iam_role.github_terraform.arn
}

output "github_actions_bootstrap_role_arn" {
  description = "GitHub Actions secret AWS_ROLE_ARN_BOOTSTRAP"
  value       = aws_iam_role.github_bootstrap.arn
}

output "aws_load_balancer_controller_irsa_role_arn" {
  description = "Used by k8s_platform stack Helm chart for aws-load-balancer-controller serviceAccount annotation."
  value       = module.lb_controller_irsa.iam_role_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
