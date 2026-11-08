output "app_task_role_arn" {
  value = module.app_identity.role_arn
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

output "rds_kms_key_arn" {
  value = module.data_keys.rds_kms_key_arn
}

output "redis_kms_key_arn" {
  value = module.data_keys.redis_kms_key_arn
}
