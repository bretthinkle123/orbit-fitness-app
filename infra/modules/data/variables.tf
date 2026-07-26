variable "name_prefix" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "aws_account_id" {
  description = "Used only to build explicit KMS key policies (Checkov CKV2_AWS_64) via string interpolation — never a live `aws_caller_identity` lookup (see root variables.tf)."
  type        = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "db_security_group_id" {
  type = string
}

variable "redis_security_group_id" {
  type = string
}

variable "master_username" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage_gb" {
  type = number
}

variable "redis_node_type" {
  type = string
}
