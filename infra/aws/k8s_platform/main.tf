data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = var.foundation_state_key
    region         = var.state_region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}

locals {
  cluster_name = data.terraform_remote_state.foundation.outputs.cluster_name
  vpc_id       = data.terraform_remote_state.foundation.outputs.vpc_id
  lb_irsa_arn  = data.terraform_remote_state.foundation.outputs.aws_load_balancer_controller_irsa_role_arn
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = local.cluster_name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = local.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = local.lb_irsa_arn
  }
}
