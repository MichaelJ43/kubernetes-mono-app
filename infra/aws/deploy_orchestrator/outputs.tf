
output "source_bucket_id" {
  value = aws_s3_bucket.source.id
}

output "api_invoke_url" {
  value       = aws_apigatewayv2_api.http.api_endpoint
  description = "Base URL for POST /deploy, /swap, /teardown (no trailing slash)."
}

output "lambda_function_name" {
  value = aws_lambda_function.orchestrator.function_name
}

output "jobs_table_name" {
  value = aws_dynamodb_table.jobs.name
}
