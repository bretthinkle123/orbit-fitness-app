# Local environment root: the same modules as infra/, pointed at moto. The modules
# are shared, never forked; local differences are module variables or provider
# configuration only. `data` (RDS/ElastiCache are compose containers) and `network`
# (VPC/SG/NAT has no local equivalent) are deliberately not composed here.
locals {
  name_prefix = "orbit-local"
  common_tags = {
    environment  = "local"
    service      = "orbit"
    "managed-by" = "terraform"
  }
}

module "app_identity" {
  source = "../../modules/app_identity"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "secrets" {
  source = "../../modules/secrets"

  name_prefix        = local.name_prefix
  tags               = local.common_tags
  aws_account_id     = var.aws_account_id
  app_task_role_name = module.app_identity.role_name

  # Moto emulates the recovery window, so a destroy-then-apply (the idempotent
  # dev-up path) would fail with ResourceExistsException at the default 30 days.
  recovery_window_in_days = 0
}

module "observability" {
  source = "../../modules/observability"

  name_prefix        = local.name_prefix
  tags               = local.common_tags
  aws_region         = var.aws_region
  aws_account_id     = var.aws_account_id
  app_task_role_name = module.app_identity.role_name

  # Referenced only in a log-policy condition, so the principal need not exist.
  ops_role_arn = "arn:aws:iam::${var.aws_account_id}:role/orbit-local-ops"
}

# RDS and ElastiCache are compose containers locally, so only their KMS keys are
# created here; that is why `data` itself is not composed.
module "data_keys" {
  source = "../../modules/data_keys"

  name_prefix    = local.name_prefix
  tags           = local.common_tags
  aws_account_id = var.aws_account_id
}
