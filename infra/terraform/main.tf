provider "aws" {
  region = var.region
  default_tags { tags = var.tags }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  fqdn         = "${var.game_subdomain}.${var.domain_name}"
  account_id   = data.aws_caller_identity.current.account_id
  cluster_tags = merge(var.tags, { Cluster = var.cluster_name })
}

# Kubernetes + Helm providers point at the cluster created below.
# No `depends_on = [module.eks]`: the cluster already exists, so the data
# sources resolve at plan time. Adding depends_on defers them until apply,
# which leaves the Helm provider with an empty config during plan whenever
# module.eks has any pending change (e.g. new access_entries).
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
