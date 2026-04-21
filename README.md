# asn2-gitops

Infrastructure-as-Code + Kubernetes manifests for the Asn2 Swing game on EKS.

The app repo ([dhruwanga19/2210](https://github.com/dhruwanga19/2210), folder
`Asn2/`) builds and pushes images to ECR. This repo provisions the cluster
they run on and holds the manifests Argo CD reconciles.

```
┌───────────────────────────────────────────────────────────────────┐
│  App repo CI                                                       │
│  ───────────                                                       │
│  gitleaks → CodeQL → hadolint → build → syft →                     │
│  trivy (fail HIGH) → push ECR → cosign sign → PR here              │
└────────────────────────┬──────────────────────────────────────────┘
                         │ merge PR (image tag bump)
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│  asn2-gitops                                                       │
│  ─────────────                                                     │
│  infra/terraform/     EKS, VPC, ECR, IAM/OIDC, ACM, Route53        │
│                       ALB controller, ExternalDNS, Kyverno,        │
│                       Argo CD, Argo CD Image Updater — all Helm.   │
│  clusters/prod/apps/  Application manifests (one per workload)     │
│  clusters/prod/workloads/                                          │
│                       Kustomize bases for each workload            │
└────────────────────────┬──────────────────────────────────────────┘
                         │ Argo CD syncs every 3 min + on git push
                         ▼
┌───────────────────────────────────────────────────────────────────┐
│  EKS cluster (prod)                                                │
│  ──────────────────                                                │
│  ns/asn2: Deployment, Service, Ingress (ALB + ACM), NetworkPolicy  │
│  ns/kyverno: no-latest-tag, require-limits, no-priv-esc,           │
│              verify-cosign-keyless-signature                       │
└───────────────────────────────────────────────────────────────────┘
```

---

## One-time bootstrap

Run once, locally, with AWS credentials that can create S3 + IAM.

```bash
cd infra/bootstrap
terraform init
terraform apply -var='region=us-east-1'
# Copy output `github_oidc_provider_arn` — it's consumed by the main stack
# automatically via a data source, so no further wiring needed.
```

This creates:

- S3 bucket for remote Terraform state (encrypted, versioned, private)
- DynamoDB state lock table
- GitHub OIDC provider

## Main stack

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your Route53 domain
terraform init
terraform apply
```

First apply takes ~15–20 min (EKS control plane + node group + addons).

### First-time bootstrap order (recommended)

If this is a brand-new environment, use this order to avoid common timing
issues around node registration and Argo CRDs:

```bash
cd infra/terraform

# 1) Build networking first (subnets, IGW, NAT, routes)
terraform apply -target=module.vpc

# 2) Build EKS + node group
terraform apply -target=module.eks

# 3) Install addons/Argo (root app is gated off by default)
terraform apply

# 4) Verify Argo Application CRD exists
aws eks update-kubeconfig --region us-east-1 --name asn2-prod
kubectl get crd applications.argoproj.io

# 5) Enable root app after CRD is present
terraform apply -var='enable_argocd_root_app=true'
```

Notes:

- `enable_argocd_root_app` defaults to `false` to prevent `kubernetes_manifest`
  from failing before Argo CRDs are available.
- After your first successful bootstrap, set
  `enable_argocd_root_app = true` in `infra/terraform/terraform.tfvars`.

### Troubleshooting quick hits

- `NodeCreationFailure: Instances failed to join the kubernetes cluster`
  usually means worker nodes launched before full VPC egress (NAT/IGW/routes)
  was in place. Apply `module.vpc` first, then `module.eks`.
- `no matches for kind "Application" in group "argoproj.io"` means Argo CD
  CRDs are not yet installed/discoverable. Install Argo first, then enable
  `enable_argocd_root_app=true` and apply again.

### Troubleshooting runbook

Use these targeted fixes when bootstrap fails partway through.

- ACM validation stuck (`aws_acm_certificate_validation.game: Still creating...`):
  verify your registrar delegates the domain to the Route53 hosted zone NS
  records. Then verify:

```bash
dig +short NS <your-domain>
dig +short CNAME <acm-validation-record>
```

ACM validation finishes only after the validation CNAME is publicly
resolvable from the authoritative nameservers.

- EKS node group error `Minimum capacity X can't be greater than desired size Y`:
  this repo's EKS module ignores Terraform drift updates to desired size on
  managed node groups, so increase desired size first via AWS API, then re-run
  Terraform:

```bash
NODEGROUP=$(aws --no-cli-pager eks list-nodegroups --cluster-name asn2-prod --region us-east-1 --query 'nodegroups[0]' --output text)
aws --no-cli-pager eks update-nodegroup-config \
  --region us-east-1 \
  --cluster-name asn2-prod \
  --nodegroup-name "$NODEGROUP" \
  --scaling-config minSize=1,maxSize=4,desiredSize=3
terraform apply -target=module.eks
```

- Kyverno upgrade rollback (`post-upgrade hooks failed`, `kyverno-clean-reports`):
  disable Kyverno cleanup hooks/cleanup jobs in Helm values and reconcile only
  Kyverno first:

```bash
terraform apply -target=helm_release.kyverno
```

In this repo, cleanup hooks and cleanup cronjobs are already disabled in
`infra/terraform/addons.tf` to prevent this failure mode.

- Argo CD Helm timeout (`context deadline exceeded`, release uninstalled due to `atomic`):
  this usually means pod scheduling pressure (`Too many pods`). Ensure node
  group capacity is scaled first, then apply Argo/full stack:

```bash
terraform apply -target=module.eks
kubectl get nodes
kubectl get pods -A --field-selector=status.phase=Pending
terraform apply
```

If pending pods show scheduler errors, increase node group capacity in
`terraform.tfvars` (`node_min_size`, `node_max_size`, `node_desired_size`) and
re-run the EKS targeted apply before full apply.

After apply, grab outputs:

```bash
terraform output kubeconfig_command      # run this to configure kubectl
terraform output github_deploy_role_arn  # store as AWS_DEPLOY_ROLE_ARN in both repos
terraform output ecr_repository_url      # update clusters/prod/workloads/asn2-game/kustomization.yaml
terraform output game_certificate_arn    # update clusters/prod/workloads/asn2-game/ingress.yaml
terraform output argocd_admin_secret_hint
```

## Argo CD UI

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80
# username: admin
# password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
# open http://localhost:8080
```

## GitOps workflow

1. Engineer pushes Java change to `dhruwanga19/2210` main.
2. App-repo CI (`.github/workflows/ci.yml`) runs all gates, pushes signed image.
3. CI opens a PR here bumping `newTag:` in
   `clusters/prod/workloads/asn2-game/kustomization.yaml`.
4. Reviewer merges. Argo CD picks it up within ~3 min and rolls the Deployment.
5. Kyverno validates the new image carries a valid cosign signature from the
   expected CI workflow before admitting the Pod.

## Layout

```
asn2-gitops/
├── infra/
│   ├── bootstrap/              one-shot: S3 state + OIDC provider
│   └── terraform/              main stack: VPC, EKS, ECR, addons, Argo CD
├── clusters/
│   └── prod/
│       ├── apps/               Argo CD Applications (one per workload)
│       │   ├── asn2-game.yaml
│       │   └── kyverno-policies.yaml
│       └── workloads/          Kustomize bases
│           ├── asn2-game/      Deployment, Service, Ingress, NetworkPolicy
│           └── kyverno-policies/
└── .github/workflows/
    ├── terraform-plan.yml      PR: Checkov + tfsec + terraform plan
    ├── terraform-apply.yml     merge to main: terraform apply (env-gated)
    └── kube-lint.yml           kubeconform + kube-linter on clusters/**
```

## Secrets to configure

- **Repo `asn2-gitops`** → Secrets:
  - `AWS_DEPLOY_ROLE_ARN` — output `github_deploy_role_arn` from Terraform.
- **Repo `2210`** → Secrets:
  - `AWS_DEPLOY_ROLE_ARN` — same value as above.
  - `GITOPS_PAT` — fine-grained PAT with `contents:write` + `pull_requests:write`
    on this repo, so the CI's "bump image tag" job can open PRs.

Also: repo settings → **Environments** → create `production` with required
reviewers, so `terraform-apply` waits for human approval.

## Verifying end-to-end

```bash
# 1. Cluster reachable
kubectl get nodes

# 2. Argo CD apps synced
kubectl -n argocd get app

# 3. Game pod healthy
kubectl -n asn2 get pods

# 4. ALB provisioned
kubectl -n asn2 get ingress

# 5. TLS resolving
curl -sI https://game.<your-domain>/ | head -n 5

# 6. Cosign signature verifies
cosign verify \
  --certificate-identity-regexp 'https://github.com/dhruwanga19/2210' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  $(kubectl -n asn2 get pod -o jsonpath='{.items[0].spec.containers[0].image}')
```

## Teardown

```bash
cd infra/terraform && terraform destroy
cd ../bootstrap && terraform destroy
```

The Route53 hosted zone is imported (data source) so `destroy` leaves it
intact — only ACM records this stack created are removed.

## Cost

~$125 / month baseline (EKS control plane $73, 2 × t3.small $30, ALB $18,
NAT gateway $32). Halve the NAT cost by switching to a single NAT (`vpc.tf`
already does) and pulling nodes down to 1 at night with a cron-based HPA.
