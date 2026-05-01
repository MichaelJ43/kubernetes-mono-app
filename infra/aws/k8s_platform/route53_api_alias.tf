# After Argo syncs the API Ingress, the AWS Load Balancer Controller tags the ALB with
# ingress.k8s.aws/stack = "<namespace>/<ingress name>" (implicit group). We find that ALB
# and create the public DNS name for the API. First apply may create no record until the
# ALB exists—re-run terraform apply (or rely on the next infra merge / workflow).

locals {
  api_ingress_stack_id = "${var.api_ingress_namespace}/${var.api_ingress_name}"
}

data "aws_resourcegroupstaggingapi_resources" "api_ingress_alb" {
  count = local.enable_external_dns ? 1 : 0

  resource_type_filters = ["elasticloadbalancing:loadbalancer"]

  tag_filter {
    key    = "elbv2.k8s.aws/cluster"
    values = [local.cluster_name]
  }

  tag_filter {
    key    = "ingress.k8s.aws/stack"
    values = [local.api_ingress_stack_id]
  }
}

locals {
  api_alb_tag_mappings = local.enable_external_dns ? data.aws_resourcegroupstaggingapi_resources.api_ingress_alb[0].resource_tag_mapping_list : []
  api_alb_arn          = length(local.api_alb_tag_mappings) > 0 ? local.api_alb_tag_mappings[0].resource_arn : null
}

data "aws_lb" "api_ingress" {
  count = local.api_alb_arn != null ? 1 : 0
  arn   = local.api_alb_arn
}

locals {
  create_api_route53_alias = local.api_alb_arn != null
}

resource "aws_route53_record" "api_alias_ipv4" {
  count   = local.create_api_route53_alias ? 1 : 0
  zone_id = var.external_dns_route53_zone_id
  name    = "api"
  type    = "A"

  alias {
    name                   = data.aws_lb.api_ingress[0].dns_name
    zone_id                = data.aws_lb.api_ingress[0].zone_id
    evaluate_target_health = true
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "aws_route53_record" "api_alias_ipv6" {
  # Do not index [0] when data.aws_lb has count 0 — Terraform may still evaluate both operands of &&.
  count   = try(data.aws_lb.api_ingress[0].ip_address_type, null) == "dualstack" ? 1 : 0
  zone_id = var.external_dns_route53_zone_id
  name    = "api"
  type    = "AAAA"

  alias {
    name                   = data.aws_lb.api_ingress[0].dns_name
    zone_id                = data.aws_lb.api_ingress[0].zone_id
    evaluate_target_health = true
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
