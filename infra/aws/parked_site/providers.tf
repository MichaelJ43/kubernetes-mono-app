provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "kubernetes-mono-app"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront viewer certificates must be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "kubernetes-mono-app"
      ManagedBy = "terraform"
    }
  }
}
