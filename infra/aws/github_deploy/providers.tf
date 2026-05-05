provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project   = "kubernetes-mono-app"
      ManagedBy = "terraform"
    }
  }
}
