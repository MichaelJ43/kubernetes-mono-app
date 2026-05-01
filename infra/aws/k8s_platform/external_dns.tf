locals {
  enable_external_dns = var.external_dns_route53_zone_id != null && var.external_dns_route53_zone_id != ""
}

data "aws_route53_zone" "external_dns" {
  count   = local.enable_external_dns ? 1 : 0
  zone_id = var.external_dns_route53_zone_id
}

locals {
  external_dns_domain = local.enable_external_dns ? trimsuffix(data.aws_route53_zone.external_dns[0].name, ".") : null
}

data "aws_iam_policy_document" "external_dns" {
  count = local.enable_external_dns ? 1 : 0

  statement {
    sid    = "ChangeRecordsInZone"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${var.external_dns_route53_zone_id}",
    ]
  }

  statement {
    sid    = "ListZonesAndRecords"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  count  = local.enable_external_dns ? 1 : 0
  name   = "${local.cluster_name}-external-dns"
  policy = data.aws_iam_policy_document.external_dns[0].json
}

# EKS IRSA uses the cluster OIDC provider in IAM. Resolve it from the live cluster
# so PR plans work even when foundation remote state predates output oidc_provider_arn.
data "aws_iam_openid_connect_provider" "cluster" {
  count = local.enable_external_dns ? 1 : 0
  url   = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"
  count   = local.enable_external_dns ? 1 : 0

  role_name = "${local.cluster_name}-external-dns"

  role_policy_arns = {
    external_dns = aws_iam_policy.external_dns[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = data.aws_iam_openid_connect_provider.cluster[0].arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

resource "helm_release" "external_dns" {
  count = local.enable_external_dns ? 1 : 0
  name  = "external-dns"

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.21.1"
  namespace  = "kube-system"

  depends_on = [helm_release.aws_load_balancer_controller]

  values = [
    yamlencode({
      provider = { name = "aws" }
      env = [
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
      ]
      domainFilters = [local.external_dns_domain]
      txtOwnerId    = "${local.cluster_name}-external-dns"
      policy        = "upsert-only"
      sources       = ["ingress"]
      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_dns_irsa[0].iam_role_arn
        }
      }
    })
  ]
}
