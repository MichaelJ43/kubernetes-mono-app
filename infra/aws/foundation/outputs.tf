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
  description = "Typical value for GitHub Actions secret AWS_DEPLOY_ROLE_ARN (Terraform + Argo workflows)."
  value       = aws_iam_role.github_terraform.arn
}

output "github_actions_bootstrap_role_arn" {
  description = "Optional narrow GitOps role (if not using a single AWS_DEPLOY_ROLE_ARN)"
  value       = aws_iam_role.github_bootstrap.arn
}

output "aws_load_balancer_controller_irsa_role_arn" {
  description = "Used by k8s_platform stack Helm chart for aws-load-balancer-controller serviceAccount annotation."
  value       = module.lb_controller_irsa.iam_role_arn
}

output "acm_certificate_arn" {
  description = "When acm_certificate_arn or acm_certificate_domain yields a cert, that ARN (optional; Argo Ingress uses discovery without this in Git)."
  value = (
    var.acm_certificate_arn != null && var.acm_certificate_arn != ""
    ) ? var.acm_certificate_arn : (
    length(data.aws_acm_certificate.ingress) > 0 ? data.aws_acm_certificate.ingress[0].arn : null
  )
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "oidc_provider_arn" {
  description = "EKS IRSA OIDC provider ARN (for additional IRSA roles in k8s_platform, e.g. ExternalDNS)."
  value       = module.eks.oidc_provider_arn
}
