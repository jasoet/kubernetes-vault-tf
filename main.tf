# Vault Secret Engine
resource "vault_mount" "demo-kv2-engine" {
  path        = "demo"
  type        = "kv-v2"
  description = "Secret KV (version 2) engine to store demo Secrets"
}

# Vault policies
resource "vault_policy" "demo-write" {
  name   = "demo-write"
  policy = <<EOT
path "demo/*" {
       capabilities =  ["create", "read", "update", "delete", "list", "sudo"]
}
EOT
}

resource "vault_policy" "demo-read" {
  name   = "demo-read"
  policy = <<EOT
path "demo/*" {
       capabilities =  ["read", "list"]
}
EOT
}

# Vault token backend role
resource "vault_token_auth_backend_role" "demo-backend-role" {
  depends_on = [vault_policy.demo-write]

  role_name        = "demo-backend-role"
  allowed_policies = ["demo-write"]
  token_period     = 86400000
  orphan           = true
  renewable        = true
}

# Vault token for demo secret
resource "vault_token" "demo-secret-token" {
  depends_on = [vault_token_auth_backend_role.demo-backend-role]

  role_name = "demo-backend-role"
  policies  = ["demo-write"]
  renewable = true
}

# Vault write a new secret
resource "vault_generic_secret" "demo-app-secret" {
  depends_on = [vault_mount.demo-kv2-engine]
  path       = "demo/app/config"

  data_json = <<EOT
{
  "password": "jasoet",
  "username": "localhost"
}
EOT
}

# Kubernetes to Allows Vault Auth from Kubernetes
resource "kubernetes_service_account" "vault-auth" {
  metadata {
    name = "vault-auth"
  }
}

resource "kubernetes_secret" "vault-auth" {
  metadata {
    name = "vault-auth"
    annotations = {
      "kubernetes.io/service-account.name" = "vault-auth"
    }
  }
  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_cluster_role_binding" "role-tokenreview-binding" {
  metadata {
    name = "role-tokenreview-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "vault-auth"
    namespace = "default"
  }
}

# Configure Vault to enable Kubernetes Auth
resource "vault_auth_backend" "kubernetes-auth-backend" {
  type = "kubernetes"
  path = "do-k8s"
}

data "kubernetes_secret" "auth-secret-data" {
  depends_on = [kubernetes_secret.vault-auth]
  metadata {
    name = "vault-auth"
  }
}

resource "vault_kubernetes_auth_backend_config" "kubernetes-host" {
  backend            = vault_auth_backend.kubernetes-auth-backend.path
  kubernetes_host    = local.kubernetes_host
  kubernetes_ca_cert = base64decode(local.kuberntes_ca_cert)
  token_reviewer_jwt = data.kubernetes_secret.auth-secret-data.data["token"]
}

resource "vault_kubernetes_auth_backend_role" "kubernetes-role" {
  backend                          = vault_auth_backend.kubernetes-auth-backend.path
  role_name                        = "kubernetes-role"
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = [vault_policy.demo-write.name]
}

resource "helm_release" "vault-injector" {
  repository = "https://helm.releases.hashicorp.com"
  name       = "vault"
  chart      = "vault"

  set {
    name  = "injector.externalVaultAddr"
    value = local.vault_addr
  }

}
