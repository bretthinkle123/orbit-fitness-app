variable "name_prefix" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "aws_region" {
  description = "Used to scope the log groups' KMS key policy to the CloudWatch Logs service principal for this region (a plain variable, not a live lookup)."
  type        = string
}

variable "aws_account_id" {
  description = "Used only to build an explicit KMS key policy (Checkov CKV2_AWS_64) via string interpolation — never a live `aws_caller_identity` lookup (see root variables.tf)."
  type        = string
}

variable "app_task_role_name" {
  description = "IAM role name the log-write + X-Ray-write policies attach to."
  type        = string
}

variable "ops_role_arn" {
  description = "The single principal exempted from the log delete-deny policy (plan.md §Logging)."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 90
}
