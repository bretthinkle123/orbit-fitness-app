output "database_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "database_master_user_secret_arn" {
  description = "The RDS-MANAGED master-password secret's ARN — a DIFFERENT secret than modules/secrets' `database_url` container (see this module's main.tf comment on that separation)."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "db_kms_key_arn" {
  value = aws_kms_key.rds.arn
}
