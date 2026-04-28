data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint,
  ]

  tags = {
    Name = "github-actions-oidc"
  }
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_organization}/${var.github_repository}:*",
      ]
    }
  }
}

# Uses AdministratorAccess for portfolio simplicity; scope down for production.
resource "aws_iam_role" "github_terraform" {
  name               = "${var.cluster_name}-gha-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

resource "aws_iam_role_policy_attachment" "github_terraform_admin" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_policy" "github_bootstrap_aws_api" {
  name        = "${var.cluster_name}-gha-bootstrap-aws-api"
  description = "AWS API calls for update-kubeconfig; cluster RBAC via EKS access entry"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "github_bootstrap" {
  name                 = "${var.cluster_name}-gha-bootstrap"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_bootstrap" {
  role       = aws_iam_role.github_bootstrap.name
  policy_arn = aws_iam_policy.github_bootstrap_aws_api.arn
}
