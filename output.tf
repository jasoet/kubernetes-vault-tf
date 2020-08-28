output "demo-token" {
  value = vault_token.demo-secret-token.client_token
}

output "demo-auth-jwt" {
  value = data.kubernetes_secret.auth-secret-data.data["token"]
}
