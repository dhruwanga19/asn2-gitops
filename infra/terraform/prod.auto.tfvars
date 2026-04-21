region      = "us-east-1"
domain_name = "dhruwang.dev"

node_instance_types = ["t3.large"]
node_min_size       = 1
node_max_size       = 3
node_desired_size   = 1

# Root Argo CD Application (app-of-apps) that fans out to clusters/prod/apps.
# Created by the initial local bootstrap; keep true so CI doesn't destroy it.
enable_argocd_root_app = true
