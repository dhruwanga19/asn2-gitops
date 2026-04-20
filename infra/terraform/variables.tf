variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "asn2-prod"
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

# Route53 zone you already own. Override in terraform.tfvars.
variable "domain_name" {
  type        = string
  description = "Apex domain with an existing Route53 public hosted zone."
  default     = "example.com"
}

variable "game_subdomain" {
  type        = string
  description = "Host prefix — final URL becomes <game_subdomain>.<domain_name>."
  default     = "game"
}

# Worker node sizing
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# GitHub repos allowed to assume the deploy role via OIDC.
variable "github_owner" {
  type    = string
  default = "dhruwanga19"
}

variable "github_app_repo" {
  type        = string
  description = "Repo that builds and pushes images."
  default     = "2210"
}

variable "github_gitops_repo" {
  type        = string
  description = "Repo holding this Terraform + k8s manifests."
  default     = "asn2-gitops"
}

# ECR repository name for the Swing game image.
variable "ecr_repo_name" {
  type    = string
  default = "asn2-game"
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "asn2-gitops"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
