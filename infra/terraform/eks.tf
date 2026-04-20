module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Public control-plane endpoint, restricted to the internet but still
  # preferable to locate behind a CIDR list in production. Left open here
  # so GitHub Actions can hit the API server for helm releases.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # OIDC provider for IRSA — the module creates its own; we reuse it for the
  # IRSA roles defined in iam.tf.
  enable_irsa = true

  # AWS-managed cluster addons. kube-proxy + CoreDNS + VPC CNI get lifecycle
  # management for free.
  cluster_addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
  }

  # Managed node group. Small, private, on-demand.
  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      labels = {
        workload = "general"
      }

      # Encrypt the node EBS root volume.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }

  # Grant cluster-admin to the caller identity running `terraform apply`.
  # In production this would be replaced by SSO groups via
  # `access_entries` + `access_policy_associations`.
  enable_cluster_creator_admin_permissions = true

  tags = local.cluster_tags
}
