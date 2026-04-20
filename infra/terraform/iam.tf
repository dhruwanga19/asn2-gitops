# -------------------------------------------------------------------------
# GitHub OIDC provider (created in ../bootstrap) + deploy role the Actions
# workflows assume. Scoped tightly to the specific repos + branches.
# -------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_sub_claims = [
    # App repo: any workflow running on main or any PR from main branch
    "repo:${var.github_owner}/${var.github_app_repo}:ref:refs/heads/main",
    "repo:${var.github_owner}/${var.github_app_repo}:pull_request",
    # GitOps repo: main + plan on PRs
    "repo:${var.github_owner}/${var.github_gitops_repo}:ref:refs/heads/main",
    "repo:${var.github_owner}/${var.github_gitops_repo}:pull_request",
  ]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_sub_claims
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.cluster_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

# The role needs to: push to the single ECR repo, read its digest, and
# (for the gitops repo) call EKS to verify the cluster is reachable.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.asn2_game.arn]
  }

  statement {
    sid       = "EcrGetAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EksDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

# -------------------------------------------------------------------------
# IRSA roles for in-cluster addons. Each gets a k8s ServiceAccount pointing
# at the IAM role ARN via `eks.amazonaws.com/role-arn` annotation.
# The annotation is set by the Helm values in addons.tf.
# -------------------------------------------------------------------------

# --- AWS Load Balancer Controller ---
module "irsa_alb" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                              = "${var.cluster_name}-aws-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# --- External DNS ---
module "irsa_external_dns" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                     = "${var.cluster_name}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [data.aws_route53_zone.apex.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

# --- Argo CD Image Updater (reads ECR tags) ---
data "aws_iam_policy_document" "image_updater" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = ["*"]
  }
}

module "irsa_image_updater" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${var.cluster_name}-argocd-image-updater"
  role_policy_arns = {
    ecr_read = aws_iam_policy.image_updater.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["argocd:argocd-image-updater"]
    }
  }
}

resource "aws_iam_policy" "image_updater" {
  name   = "${var.cluster_name}-argocd-image-updater"
  policy = data.aws_iam_policy_document.image_updater.json
}
