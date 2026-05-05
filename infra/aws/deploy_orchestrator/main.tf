locals {
  name_safe = replace(lower(var.github_repository), "/", "-")
}

data "terraform_remote_state" "foundation" {
  count   = var.foundation_state_key != "" ? 1 : 0
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = var.foundation_state_key
    region         = var.state_region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}

data "terraform_remote_state" "parked_site" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = var.parked_site_state_key
    region         = var.state_region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}

data "aws_caller_identity" "current" {}

# From foundation state (if loaded). Empty if no key, missing output, or wrong type.
locals {
  cluster_name_candidate = length(data.terraform_remote_state.foundation) > 0 ? try(trimspace(tostring(data.terraform_remote_state.foundation[0].outputs["cluster_name"])), "") : ""
}

# Only wire EKS when the cluster name from state still exists (avoids plan failure after cluster destroy with stale state).
data "aws_eks_clusters" "regional" {}

locals {
  enable_eks = local.cluster_name_candidate != "" && contains(data.aws_eks_clusters.regional.names, local.cluster_name_candidate)
}

data "aws_eks_cluster" "this" {
  count = local.enable_eks ? 1 : 0
  name  = local.cluster_name_candidate
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/package"
  output_path = "${path.module}/lambda_bundle.zip"
}

resource "random_id" "suffix" {
  byte_length = 2
}

resource "aws_s3_bucket" "source" {
  bucket = substr("${local.name_safe}-deploy-src-${random_id.suffix.hex}", 0, 63)

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "jobs" {
  name         = substr("${local.name_safe}-deploy-jobs-${random_id.suffix.hex}", 0, 255)
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = substr("${local.name_safe}-deploy-orc-${random_id.suffix.hex}", 0, 64)
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_core" {
  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid = "SourceS3"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.source.arn,
      "${aws_s3_bucket.source.arn}/*",
    ]
  }

  statement {
    sid = "ParkedS3"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.parked_site.outputs.s3_bucket_id}",
      "arn:aws:s3:::${data.terraform_remote_state.parked_site.outputs.s3_bucket_id}/*",
    ]
  }

  statement {
    sid = "CloudFront"
    actions = [
      "cloudfront:CreateInvalidation",
    ]
    resources = [
      "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${data.terraform_remote_state.parked_site.outputs.cloudfront_distribution_id}",
    ]
  }

  statement {
    sid = "SSM"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]
    resources = ["arn:aws:ssm:*:*:parameter/kubernetes-mono-app/*"]
  }

  statement {
    sid = "DynamoDBJobs"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.jobs.arn]
  }

  statement {
    sid = "LambdaAsyncSelf"
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "lambda_eks" {
  count = local.enable_eks ? 1 : 0
  statement {
    sid = "EKS"
    actions = [
      "eks:DescribeCluster",
    ]
    resources = [data.aws_eks_cluster.this[0].arn]
  }
}

data "aws_iam_policy_document" "lambda_merged" {
  source_policy_documents = concat(
    [data.aws_iam_policy_document.lambda_core.json],
    local.enable_eks ? [data.aws_iam_policy_document.lambda_eks[0].json] : []
  )
}

resource "aws_iam_role_policy" "lambda" {
  name   = "deploy-orchestrator"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_merged.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_safe}-deploy-orc-${random_id.suffix.hex}"
  retention_in_days = 14
}

resource "aws_lambda_function" "orchestrator" {
  function_name = substr("${local.name_safe}-deploy-orc-${random_id.suffix.hex}", 0, 64)
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 900
  memory_size   = 512

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.lambda]

  environment {
    variables = {
      SITE_MODE_PARAM = var.site_mode_parameter_name
      SOURCE_BUCKET   = aws_s3_bucket.source.id
      PARKED_BUCKET   = data.terraform_remote_state.parked_site.outputs.s3_bucket_id
      PARKED_CF_ID    = data.terraform_remote_state.parked_site.outputs.cloudfront_distribution_id
      JOB_TABLE       = aws_dynamodb_table.jobs.name
      EKS_ENABLED     = local.enable_eks ? "1" : "0"
      CLUSTER_NAME    = local.enable_eks ? data.aws_eks_cluster.this[0].name : ""
      EKS_ENDPOINT    = local.enable_eks ? data.aws_eks_cluster.this[0].endpoint : ""
      EKS_CA_B64      = local.enable_eks ? data.aws_eks_cluster.this[0].certificate_authority[0].data : ""
      AWS_REGION_NAME = var.aws_region
    }
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = substr("${local.name_safe}-deploy-api-${random_id.suffix.hex}", 0, 128)
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.orchestrator.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "deploy" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /deploy"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "swap" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /swap"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "teardown" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /teardown"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.http.id}/*/*"
}

resource "aws_eks_access_entry" "lambda" {
  count         = local.enable_eks ? 1 : 0
  cluster_name  = data.aws_eks_cluster.this[0].name
  principal_arn = aws_iam_role.lambda.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "lambda_admin" {
  count         = local.enable_eks ? 1 : 0
  cluster_name  = aws_eks_access_entry.lambda[0].cluster_name
  principal_arn = aws_eks_access_entry.lambda[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_ssm_parameter" "deploy_api_url" {
  name  = "/kubernetes-mono-app/deploy_orchestrator_api_url"
  type  = "String"
  value = aws_apigatewayv2_api.http.api_endpoint

  overwrite = true
}
