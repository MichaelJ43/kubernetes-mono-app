output "aws_load_balancer_controller_release" {
  value       = helm_release.aws_load_balancer_controller.name
  description = "Helm release name for AWS Load Balancer Controller"
}

output "external_dns_release" {
  value       = try(helm_release.external_dns[0].name, null)
  description = "Helm release name for ExternalDNS when external_dns_route53_zone_id is set"
}

output "api_route53_fqdn" {
  description = <<-EOT
    Public API hostname (api.<delegated zone>) when external_dns_route53_zone_id is set.
    The Route53 alias exists after the tagged ALB is found; null until then—re-run apply if needed.
  EOT
  value       = local.enable_external_dns ? "api.${local.external_dns_domain}" : null
}

output "api_route53_alias_managed" {
  description = "True when Terraform created the api A Record in Route 53 (ALB was discoverable)."
  value       = length(aws_route53_record.api_alias_ipv4) > 0
}
