output "aws_load_balancer_controller_release" {
  value       = helm_release.aws_load_balancer_controller.name
  description = "Helm release name for AWS Load Balancer Controller"
}

output "external_dns_release" {
  value       = try(helm_release.external_dns[0].name, null)
  description = "Helm release name for ExternalDNS when external_dns_route53_zone_id is set"
}
