# In-cluster addons installed via Helm. We deliberately use Helm from
# Terraform here (as opposed to GitOps-ing them) because these are
# prerequisites for Argo CD itself to become self-sufficient.
#
# After bootstrap is complete, Argo CD manages its own upgrades + the
# asn2-game workload. Terraform retains ownership of infrastructure-level
# addons so node-replacement flows keep them in sync.

# ---------------- AWS Load Balancer Controller ----------------
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.2"
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    region      = var.region
    vpcId       = module.vpc.vpc_id
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.irsa_alb.iam_role_arn
      }
    }
  })]

  depends_on = [module.eks]
}

# ---------------- External DNS ----------------
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.15.0"
  namespace  = "kube-system"

  values = [yamlencode({
    provider       = "aws"
    policy         = "sync"
    registry       = "txt"
    txtOwnerId     = var.cluster_name
    domainFilters  = [var.domain_name]
    sources        = ["ingress"]
    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.irsa_external_dns.iam_role_arn
      }
    }
  })]

  depends_on = [module.eks]
}

# ---------------- Metrics Server (HPA, kubectl top) ----------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  namespace  = "kube-system"

  values = [yamlencode({
    args = ["--kubelet-insecure-tls"] # EKS kubelet uses self-signed certs
  })]

  depends_on = [module.eks]
}

# ---------------- Kyverno (policy engine) ----------------
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = "3.2.6"
  namespace        = "kyverno"
  create_namespace = true

  depends_on = [module.eks]
}

# ---------------- Argo CD (GitOps controller) ----------------
resource "random_password" "argocd_admin" {
  length  = 24
  special = false
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.12"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    global = {
      domain = "argocd.${var.domain_name}" # for the UI (optional, not exposed by default)
    }
    configs = {
      params = {
        # Headless install — disable the Argo CD internal TLS on the server since
        # the ALB (when added later) terminates TLS. For this demo we only
        # port-forward the UI; no ingress.
        "server.insecure" = true
      }
      secret = {
        # Override the auto-generated bcrypt admin password with a known one.
        # bcrypt the random_password via local-exec? Argo CD accepts a
        # pre-hashed value via `argocdServerAdminPassword`. Simpler: let
        # Argo CD generate its own and retrieve via `kubectl get secret
        # argocd-initial-admin-secret`. Documented in README.
      }
    }
    server = {
      extraArgs = ["--insecure"]
    }
    controller = {
      # Sync period: check git every 3 minutes even without webhooks.
      env = [{ name = "ARGOCD_RECONCILIATION_TIMEOUT", value = "180s" }]
    }
  })]

  depends_on = [
    helm_release.aws_lb_controller,
    helm_release.external_dns,
    helm_release.kyverno,
  ]
}

# ---------------- Argo CD Image Updater ----------------
resource "helm_release" "argocd_image_updater" {
  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = "0.11.0"
  namespace  = "argocd"

  values = [yamlencode({
    serviceAccount = {
      create = true
      name   = "argocd-image-updater"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.irsa_image_updater.iam_role_arn
      }
    }
    config = {
      registries = [{
        name     = "ECR"
        api_url  = "https://${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
        prefix   = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
        ping     = true
        insecure = false
        # IRSA creds -> use the AWS CLI credential helper shipped in the image.
        credentials = "ext:/scripts/auth1.sh"
        credsexpire = "10h"
      }]
    }
    # Small shim that prints `AWS:<token>` for the helper; uses IRSA automatically.
    extraArgs = []
  })]

  depends_on = [helm_release.argocd]
}
