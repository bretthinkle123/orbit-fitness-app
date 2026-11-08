variable "name_prefix" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "aws_account_id" {
  description = "Used only to build explicit KMS key policies (Checkov CKV2_AWS_64) via string interpolation - never a live `aws_caller_identity` lookup (see root variables.tf)."
  type        = string
}
