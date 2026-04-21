data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  vpc_cidr = "10.60.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.cluster_name}-vpc"
  cidr = local.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(local.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(local.vpc_cidr, 4, i + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # single NAT keeps cost low; acceptable for a demo
  enable_dns_hostnames = true

  # Tags required by AWS Load Balancer Controller to place the ALB in the
  # correct subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
