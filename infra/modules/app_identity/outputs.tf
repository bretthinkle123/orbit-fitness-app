output "role_name" {
  description = "IAM role name, for `aws_iam_role_policy.role` attachments."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
