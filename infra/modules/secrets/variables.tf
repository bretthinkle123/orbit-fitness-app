variable "name_prefix" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "aws_account_id" {
  description = "Used only to build an explicit KMS key policy (Checkov CKV2_AWS_64) via string interpolation — never a live `aws_caller_identity` lookup (see root variables.tf)."
  type        = string
}

variable "app_task_role_name" {
  description = "IAM role name (not ARN — `aws_iam_role_policy.role` takes a name/id) the least-privilege secrets-read policy attaches to."
  type        = string
}
