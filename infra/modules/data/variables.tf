variable "name_prefix" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "rds_kms_key_arn" {
  description = "CMK for RDS storage encryption and Performance Insights (from modules/data_keys)."
  type        = string
}

variable "redis_kms_key_arn" {
  description = "CMK for ElastiCache at-rest encryption (from modules/data_keys)."
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
