output "deploy_role_arn" {
  description = "The OIDC deploy role ARN CI assumes before running Terraform (documented here for that tooling to read, rather than a second, hardcoded copy in CI YAML)."
  value       = var.deploy_role_arn
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "app_task_role_arn" {
  value = aws_iam_role.app_task.arn
}

output "database_endpoint" {
  description = "RDS endpoint (host:port) — never the credential; the app fetches the full DSN from Secrets Manager instead (modules/secrets)."
  value       = module.data.database_endpoint
}

output "redis_primary_endpoint" {
  value = module.data.redis_primary_endpoint
}

output "database_url_secret_arn" {
  value = module.secrets.database_url_secret_arn
}

output "firebase_admin_credentials_secret_arn" {
  value = module.secrets.firebase_admin_credentials_secret_arn
}

output "app_log_group_name" {
  value = module.observability.app_log_group_name
}

output "audit_log_group_name" {
  value = module.observability.audit_log_group_name
}
