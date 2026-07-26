variable "aws_region" {
  description = "AWS region the stack is provisioned in."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name, used in resource naming/tags. No envs/ split this run (compute topology + the environments axis are deferred — plan.md Stack notes); a single environment value is enough for the data-security baseline."
  type        = string
  default     = "production"
}

variable "service_name" {
  description = "Service name, used in resource naming/tags (iac-conventions: name resources <service>-<environment>-<resource>)."
  type        = string
  default     = "orbit"
}

variable "offline_validate" {
  description = <<-EOT
    Operator addendum #4: no AWS account exists yet this run. When true (the
    default), the AWS provider uses dummy static credentials and skips every
    account-reachability check, so `terraform plan` succeeds with no live
    credentials at all. Real deploys set this to false; the CI job's
    already-assumed OIDC role then supplies real, short-lived credentials the
    provider picks up automatically from its environment (no `assume_role`
    block needed in this config — that assumption happens before Terraform
    runs at all).
  EOT
  type        = bool
  default     = true
}

variable "deploy_role_arn" {
  description = "ARN of the OIDC-assumed CI deploy role (no long-lived keys). Consumed by the CI workflow's own credential step, not by any resource in this config — declared here (and surfaced via an output) so it is one documented, typed value rather than duplicated/hardcoded in CI YAML."
  type        = string
  default     = "arn:aws:iam::123456789012:role/orbit-deploy-ci"
}

variable "ops_role_arn" {
  description = "ARN of the dedicated, human-operated ops role exempted from the CloudWatch log delete-deny policy (plan.md §Logging: \"a resource policy that denies logs:DeleteLogGroup/DeleteLogStream/PutRetentionPolicy to all but a dedicated ops role\")."
  type        = string
  default     = "arn:aws:iam::123456789012:role/orbit-ops"
}

variable "database_master_username" {
  description = "RDS master username. The master PASSWORD is never a Terraform value at all — see modules/data's `manage_master_user_password = true` — so this identifier is the only master-auth value Terraform ever holds."
  type        = string
  default     = "orbit_app"
}

variable "database_instance_class" {
  description = "RDS instance class — a data-security-baseline default; compute-topology sizing (and any production-scale review) is deferred with the rest of the compute stack (plan.md Stack notes)."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_allocated_storage_gb" {
  description = "RDS allocated storage, in GB."
  type        = number
  default     = 20
}

variable "redis_node_type" {
  description = "ElastiCache node type — the same data-security-baseline sizing posture as the RDS instance class above."
  type        = string
  default     = "cache.t4g.micro"
}

variable "aws_account_id" {
  description = "AWS account id, used ONLY to build explicit KMS key policies (Checkov CKV2_AWS_64) via plain string interpolation — deliberately NOT via the `aws_caller_identity` data source, which requires a live STS call and would break credential-less `terraform plan` (Operator addendum #4, same reasoning as the network module's avoidance of `aws_availability_zones`)."
  type        = string
  default     = "123456789012" # AWS's own well-known placeholder example account id
}
