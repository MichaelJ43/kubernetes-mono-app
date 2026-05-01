# Optional: resolve an ISSUED ACM public cert in this region (same as ALB).
# Prefer TF_VAR_acm_certificate_arn (e.g. GitHub secret TF_ACM_CERTIFICATE_ARN) for an exact ARN;
# otherwise set acm_certificate_domain for a data-source lookup by primary domain name.

data "aws_acm_certificate" "ingress" {
  count = (
    (var.acm_certificate_arn == null || var.acm_certificate_arn == "") &&
    var.acm_certificate_domain != null && var.acm_certificate_domain != ""
  ) ? 1 : 0

  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
  types       = ["AMAZON_ISSUED"]
}
