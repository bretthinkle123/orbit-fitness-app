# Root module — composes the four single-purpose child modules; nothing
# reaches around the root (`iac-conventions` facade discipline). Authored
# this run as the data-security BASELINE only (network + data + secrets +
# observability) — compute/ALB/the envs/ split are deferred with the rest of
# the compute topology (plan.md Stack notes / §Infrastructure).

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    # Source string hand-verified against the canonical Terraform Registry
    # entry (registry.terraform.io/providers/hashicorp/aws) — the standing
    # typosquat check (dependency-audit-policy). Exact-pinned; 6.52.0 was
    # published 2026-06-24 — comfortably past the >=14-day cooldown and only
    # a few minor releases behind the latest (6.56.0), so not stale under
    # the n-1 obsolescence rule either.
    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }
  }
}

locals {
  name_prefix = "${var.service_name}-${var.environment}"
  common_tags = {
    environment  = var.environment
    service      = var.service_name
    "managed-by" = "terraform"
  }
}

provider "aws" {
  region = var.aws_region

  # Credential-less `terraform plan` (Operator addendum #4 — no AWS account
  # exists yet this run): dummy static credentials + every account-
  # reachability check skipped, gated behind `var.offline_validate` (default
  # true). Real deploys set it false — the CI job's OIDC-assumed role then
  # supplies real credentials the provider reads from its own environment.
  access_key                  = var.offline_validate ? "offline-validate" : null
  secret_key                  = var.offline_validate ? "offline-validate" : null
  skip_credentials_validation = var.offline_validate
  skip_requesting_account_id  = var.offline_validate
  skip_metadata_api_check     = var.offline_validate

  default_tags {
    tags = local.common_tags
  }
}

module "network" {
  source = "./modules/network"

  name_prefix = local.name_prefix
  tags        = local.common_tags
  aws_region  = var.aws_region
}

# The app's future runtime identity (an ECS/Fargate-shaped task role — the
# compute topology itself is deferred, but the secrets/observability modules
# both need a principal to attach their least-privilege policies to now, per
# plan.md's "least-privilege task role scoped to exactly its secrets + RDS
# connect"). A later compute-topology run attaches real compute to this same
# role rather than creating a second one.
resource "aws_iam_role" "app_task" {
  name = "${local.name_prefix}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

module "data" {
  source = "./modules/data"

  name_prefix             = local.name_prefix
  tags                    = local.common_tags
  aws_account_id          = var.aws_account_id
  private_subnet_ids      = module.network.private_subnet_ids
  db_security_group_id    = module.network.db_security_group_id
  redis_security_group_id = module.network.redis_security_group_id
  master_username         = var.database_master_username
  instance_class          = var.database_instance_class
  allocated_storage_gb    = var.database_allocated_storage_gb
  redis_node_type         = var.redis_node_type
}

module "secrets" {
  source = "./modules/secrets"

  name_prefix        = local.name_prefix
  tags               = local.common_tags
  aws_account_id     = var.aws_account_id
  app_task_role_name = aws_iam_role.app_task.name
}

module "observability" {
  source = "./modules/observability"

  name_prefix        = local.name_prefix
  tags               = local.common_tags
  aws_region         = var.aws_region
  aws_account_id     = var.aws_account_id
  app_task_role_name = aws_iam_role.app_task.name
  ops_role_arn       = var.ops_role_arn
}
