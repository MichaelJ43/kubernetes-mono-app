# Optional: resolve an existing ISSUED ACM public cert in this region (same as ALB).
# Set var.acm_certificate_domain to the certificate's primary domain name from ACM console.

data "aws_acm_certificate" "ingress" {
  count = var.acm_certificate_domain != null && var.acm_certificate_domain != "" ? 1 : 0

  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
  types       = ["AMAZON_ISSUED"]
}
