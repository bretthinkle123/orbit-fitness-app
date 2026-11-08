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

variable "recovery_window_in_days" {
  description = "Days a deleted secret stays recoverable. Defaults to AWS's own 30 so prod is unchanged; the local moto environment sets 0 because moto emulates the window and a destroy-then-apply would otherwise fail with ResourceExistsException."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 (force-delete, local only) or between 7 and 30."
  }
}
