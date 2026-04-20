terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state. The bucket + lock table are created by ../bootstrap.
  # Override values via `terraform init -backend-config=...` if you rename them.
  backend "s3" {
    bucket         = "dhruwanga19-asn2-tfstate-use1"
    key            = "asn2-gitops/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dhruwanga19-asn2-tfstate-lock"
    encrypt        = true
  }
}
