output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_region" {
  value = var.region
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.asn2_game.repository_url
  description = "Image reference to push to from the app-repo CI."
}

output "github_deploy_role_arn" {
  value       = aws_iam_role.github_deploy.arn
  description = "Add this as the AWS_DEPLOY_ROLE_ARN secret in dhruwanga19/2210."
}

output "github_tf_apply_role_arn" {
  value       = aws_iam_role.github_tf_apply.arn
  description = "Add this as the AWS_TF_DEPLOY_ROLE_ARN secret in dhruwanga19/asn2-gitops."
}

output "game_fqdn" {
  value = local.fqdn
}

output "game_certificate_arn" {
  value       = aws_acm_certificate_validation.game.certificate_arn
  description = "Wire this into clusters/prod/apps/asn2-game/ingress.yaml via patch."
}

output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "argocd_admin_secret_hint" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
