output "rds_kms_key_arn" {
  value = aws_kms_key.rds.arn
}

output "redis_kms_key_arn" {
  value = aws_kms_key.redis.arn
}
