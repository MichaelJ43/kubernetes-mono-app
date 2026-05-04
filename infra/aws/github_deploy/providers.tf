provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "kubernetes-mono-app"
      ManagedBy = "terraform"
    }
  }
}
