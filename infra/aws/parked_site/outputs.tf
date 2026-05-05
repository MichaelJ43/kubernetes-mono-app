output "s3_bucket_id" {
  description = "Parked static site bucket (sync + invalidation target)."
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution for invalidation."
  value       = aws_cloudfront_distribution.site.id
}
