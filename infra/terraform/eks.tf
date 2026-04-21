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

  # `enable_cluster_creator_admin_permissions` pins the cluster-admin entry
  # to whoever happens to be running `terraform apply`. That means the entry
  # flips between local caller (root) and CI caller (github_tf_apply role),
  # causing replacements on every context switch. Use explicit access_entries
  # instead — each principal is named, stable, and visible in the config.
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    # Local admin (root account). Replace with an IAM user ARN when you
    # stop using root for day-to-day AWS work.
    root = {
      principal_arn = "arn:aws:iam::${local.account_id}:root"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    # CI role — lets the Helm/K8s providers reach the API server from GHA.
    github_tf_apply = {
      principal_arn = aws_iam_role.github_tf_apply.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = local.cluster_tags
}
