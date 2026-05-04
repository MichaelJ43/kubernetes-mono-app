locals {
  name_safe = replace(lower(var.github_repository), "/", "-")
}

resource "random_id" "suffix" {
  byte_length = 2
}

resource "aws_cloudfront_function" "status_rewrite" {
  name    = substr("${local.name_safe}-park-status-${random_id.suffix.hex}", 0, 64)
  runtime = "cloudfront-js-1.0"
  publish = true
  code    = <<-EOT
function handler(event) {
  var request = event.request;
  if (request.uri === "/status") {
    request.uri = "/status.html";
  }
  return request;
}
EOT
}

resource "aws_s3_bucket" "site" {
  bucket = substr("${local.name_safe}-parked-${random_id.suffix.hex}", 0, 63)
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.name_safe}-park-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = var.parked_aliases
  comment             = "kubernetes-mono-app parked (cluster offline)"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.status_rewrite.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_s3_bucket_public_access_block.site]
}

resource "aws_s3_bucket_policy" "site" {
  depends_on = [aws_cloudfront_distribution.site]
  bucket     = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontRead"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

data "aws_route53_zone" "parked" {
  count   = var.manage_route53_records && var.route53_zone_id != "" ? 1 : 0
  zone_id = var.route53_zone_id
}

resource "aws_route53_record" "parked_a" {
  for_each = var.manage_route53_records && var.route53_zone_id != "" ? toset(var.parked_aliases) : toset([])

  zone_id         = data.aws_route53_zone.parked[0].zone_id
  name            = each.value
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "parked_aaaa" {
  for_each = var.manage_route53_records && var.route53_zone_id != "" ? toset(var.parked_aliases) : toset([])

  zone_id         = data.aws_route53_zone.parked[0].zone_id
  name            = each.value
  type            = "AAAA"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
