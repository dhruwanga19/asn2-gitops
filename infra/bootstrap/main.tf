# Bootstrap module. Run ONCE, manually, before anything else:
#
#   cd infra/bootstrap
#   terraform init
#   terraform apply -var='region=us-east-1'
#
# Creates:
#   * S3 bucket for Terraform remote state (encrypted, versioned, public access blocked)
#   * DynamoDB table for state locking
#   * GitHub OIDC provider
#
# The main stack (../terraform) consumes the S3 backend these resources create.
# This module itself uses LOCAL state — commit nothing sensitive from its state.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket for Terraform state."
  default     = "dhruwanga19-asn2-tfstate-use1"
}

variable "state_lock_table_name" {
  type    = string
  default = "dhruwanga19-asn2-tfstate-lock"
}

# ----------------- S3 state bucket -----------------
resource "aws_s3_bucket" "tf_state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  tags = {
    Project = "asn2-gitops"
    Purpose = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------- DynamoDB state lock -----------------
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.state_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption { enabled = true }

  point_in_time_recovery { enabled = true }

  tags = {
    Project = "asn2-gitops"
    Purpose = "terraform-state-lock"
  }
}

# ----------------- GitHub OIDC provider -----------------
# Lets GitHub Actions assume an AWS role without static credentials.
# Thumbprint is fixed by GitHub — see
# https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# ----------------- Outputs -----------------
output "state_bucket" {
  value = aws_s3_bucket.tf_state.id
}

output "state_lock_table" {
  value = aws_dynamodb_table.tf_lock.id
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
