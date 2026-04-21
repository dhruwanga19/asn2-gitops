# Once Argo CD is up, Terraform applies a single root Application pointing
# at clusters/prod/. Everything else (workloads, policies, Image Updater config)
# is then managed by Argo CD itself from Git.

resource "kubernetes_manifest" "root_app" {
  for_each = var.enable_argocd_root_app ? { root = true } : {}

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
      # finalizer ensures child apps are cleaned up if this Application is deleted
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/${var.github_owner}/${var.github_gitops_repo}.git"
        targetRevision = "HEAD"
        # The "apps/" directory contains one Argo CD Application per workload.
        # This is the classic "app of apps" pattern: Terraform bootstraps one
        # Application that in turn fans out into every child Application.
        path = "clusters/prod/apps"
        directory = {
          recurse = false
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "ServerSideApply=true",
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
