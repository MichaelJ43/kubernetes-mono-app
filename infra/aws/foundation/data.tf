data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# GitHub OIDC IAM roles live in the separate github_deploy root module.
data "terraform_remote_state" "github_deploy" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = var.github_deploy_state_key
    region         = var.state_region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}
