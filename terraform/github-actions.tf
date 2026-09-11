locals {
  github_actions_owner         = "davidikundji"
  github_actions_owner_id      = "269061648"
  github_actions_repository    = "Microservices-App-Deployment-with-Terraform-AWS-EKS"
  github_actions_repository_id = "1340843455"
  github_actions_branch        = "main"
  github_actions_namespace     = "techpathway"

  github_actions_subject = "repo:${local.github_actions_owner}@${local.github_actions_owner_id}/${local.github_actions_repository}@${local.github_actions_repository_id}:ref:refs/heads/${local.github_actions_branch}"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = {
    Name = "github-actions-oidc"
  }
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid     = "GitHubActionsMainBranch"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github_actions.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        local.github_actions_subject
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name                 = "github-actions-techpathway-eks-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600

  tags = {
    Name = "github-actions-techpathway-eks-deploy"
  }
}

data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid     = "ECRAuthentication"
    effect  = "Allow"
    actions = ["ecr:GetAuthorizationToken"]

    resources = ["*"]
  }

  statement {
    sid    = "ECRImageReadWrite"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [
      for repository in aws_ecr_repository.applications :
      repository.arn
    ]
  }

  statement {
    sid     = "EKSClusterDiscovery"
    effect  = "Allow"
    actions = ["eks:DescribeCluster"]

    resources = [
      aws_eks_cluster.main.arn
    ]
  }
}

resource "aws_iam_policy" "github_actions_deploy" {
  name        = "github-actions-techpathway-eks-deploy"
  description = "Allows GitHub Actions to publish application images and deploy to the techpathway namespace."
  policy      = data.aws_iam_policy_document.github_actions_deploy.json

  tags = {
    Name = "github-actions-techpathway-eks-deploy"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions_deploy.arn
  type          = "STANDARD"

  tags = {
    Name = "github-actions-techpathway-access"
  }
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions_deploy.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [local.github_actions_namespace]
  }

  depends_on = [
    aws_eks_access_entry.github_actions
  ]
}

output "github_actions_role_arn" {
  description = "IAM role assumed by the GitHub Actions deployment workflow."
  value       = aws_iam_role.github_actions_deploy.arn
}