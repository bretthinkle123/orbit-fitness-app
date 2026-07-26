output "database_url_secret_arn" {
  value = aws_secretsmanager_secret.database_url.arn
}

output "firebase_admin_credentials_secret_arn" {
  value = aws_secretsmanager_secret.firebase_admin_credentials.arn
}
