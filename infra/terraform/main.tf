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
# The data source handles the chicken-and-egg by reading from `aws_eks_cluster`
# after it exists (terraform handles the ordering via reference).
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
