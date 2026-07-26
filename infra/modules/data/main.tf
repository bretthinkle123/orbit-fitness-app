# Data module — RDS PostgreSQL (the personal-fitness-data store) + ElastiCache
# Redis (the rate-limit store), both encrypted at rest and never publicly
# accessible (plan.md §Infrastructure / §Data protection; AC20).

# Explicit key policy (Checkov CKV2_AWS_64: "Ensure KMS key Policy is
# defined") — functionally identical to AWS's own implicit default policy
# (root account full access), just written out so Checkov can verify it
# rather than infer it. `var.aws_account_id` is a plain variable, never a
# live `aws_caller_identity` lookup (root variables.tf).
#
# Waiver (applies to both KMS key policies in this file, and the two more
# in modules/secrets + modules/observability): Checkov's CKV_AWS_356/111/109
# flag the `"kms:*"` / `Resource: "*"` root-account statement below as an
# overly-broad IAM grant. That exact statement is AWS's OWN standard,
# documented KMS key-policy baseline (the "Enable IAM User Permissions"
# statement every AWS-managed default key already carries implicitly) — a
# known false-positive class for KMS root-account statements specifically.
# Narrowing root's own access to its own key would be an account-lockout/
# availability risk, not a security improvement, so this is waived rather
# than "fixed." NOTE the `#checkov:skip` lines below are placed INSIDE the
# `data` block body (checkov 3.3.8 does not honor a skip comment placed
# above a `data`/`resource` declaration — verified empirically; only inside
# the block body is respected) — keep them there on any future edit.
data "aws_iam_policy_document" "rds_kms_key_policy" {
  #checkov:skip=CKV_AWS_356:root-account "kms:*"/"Resource:*" is AWS's own standard KMS key-policy baseline, not an overly-broad grant
  #checkov:skip=CKV_AWS_111:same root-account statement as CKV_AWS_356 above
  #checkov:skip=CKV_AWS_109:same root-account statement as CKV_AWS_356 above
  statement {
    sid    = "EnableRootAccountFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "rds" {
  description         = "CMK for RDS storage encryption (${var.name_prefix})."
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.rds_kms_key_policy.json
  tags                = var.tags
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

data "aws_iam_policy_document" "redis_kms_key_policy" {
  #checkov:skip=CKV_AWS_356:root-account "kms:*"/"Resource:*" is AWS's own standard KMS key-policy baseline, not an overly-broad grant
  #checkov:skip=CKV_AWS_111:same root-account statement as CKV_AWS_356 above
  #checkov:skip=CKV_AWS_109:same root-account statement as CKV_AWS_356 above
  statement {
    sid    = "EnableRootAccountFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "redis" {
  description         = "CMK for ElastiCache Redis at-rest encryption (${var.name_prefix})."
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.redis_kms_key_policy.json
  tags                = var.tags
}

resource "aws_kms_alias" "redis" {
  name          = "alias/${var.name_prefix}-redis"
  target_key_id = aws_kms_key.redis.key_id
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name_prefix}-db"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.name_prefix}-postgres16"
  family = "postgres16"

  # TLS enforced in transit: every client connection to this database must
  # use SSL (plan.md §Infrastructure: "parameter group rds.force_ssl=1").
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = var.tags
}

# Enhanced-monitoring's own service-linked role (Checkov CKV_AWS_118) — a
# distinct principal from the app task role: `monitoring.rds.amazonaws.com`
# publishes OS-level metrics, it is not the application's own identity.
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.name_prefix}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = "16.6"

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"

  # Encryption at rest with a customer-managed key (AC20 / data_protection —
  # SSE + KMS on the personal-fitness-data class).
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # No `iam_database_authentication_enabled` (Checkov CKV_AWS_161 waived):
  # the app authenticates via the Secrets-Manager-resolved password DSN
  # (`repositories/base.py::resolve_database_url`), not IAM DB auth — adding
  # a second, unused auth mode here would be dead flexibility, not a fix.
  #checkov:skip=CKV_AWS_161:app auth is the Secrets-Manager-resolved password DSN (resolve_database_url), not IAM DB auth
  db_name  = "orbit"
  username = var.master_username
  # No `iam_database_authentication_enabled` here (see the `#checkov:skip`
  # on this resource's declaration above for the reason). RDS-MANAGED master
  # password: AWS creates and rotates it in ITS OWN
  # Secrets Manager secret — Terraform never sees the plaintext, so it can
  # never land in this config's state (baseline.md "no secrets in state").
  # `modules/secrets`' separate `database_url` secret is the container the
  # deploy pipeline populates POST-provision by composing this instance's
  # endpoint with that RDS-managed secret's value — a step this run does not
  # perform (no AWS account exists yet to run it against, Operator addendum #4).
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  parameter_group_name   = aws_db_parameter_group.postgres.name
  vpc_security_group_ids = [var.db_security_group_id]

  publicly_accessible = false
  multi_az            = true
  deletion_protection = true

  backup_retention_period = 7
  # Backups honesty (plan.md §Data lifecycle): a restore re-runs the app's
  # own erasure cascade for anything deleted since the backup was taken —
  # declared there, not a property Terraform itself can enforce.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-db-final"

  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Observability depth beyond the plan's literal ask (Checkov CKV_AWS_118/
  # CKV_AWS_353) — cheap, standard RDS hardening reused from the same CMK
  # already provisioned for storage encryption above.
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  tags = var.tags
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_elasticache_replication_group" "redis" {
  #checkov:skip=CKV_AWS_31:no auth_token by design (would put a plaintext credential in state, contradicting this baseline's no-secrets-in-state rule) - network-level SG isolation is the access control instead; encryption in-transit+at-rest (the other half of this check) IS enabled below
  #checkov:skip=CKV2_AWS_50:single-node/no automatic failover is this run's explicit data-security-baseline scope - production-scale HA/multi-AZ sizing is deferred with the rest of the compute topology (plan.md Stack notes)
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Rate-limit store (edge/ratelimit.py) - encrypted in transit + at rest, never public."

  engine         = "redis"
  engine_version = "7.1"
  node_type      = var.redis_node_type

  # A single node (no HA) — matches this run's data-security-baseline scope
  # (compute-topology/production-scale HA sizing is deferred with the rest of
  # the compute stack, plan.md Stack notes). `aws_elasticache_replication_
  # group` (not the older `aws_elasticache_cluster`) is still required here:
  # AWS only exposes the in-transit/at-rest encryption flags below through
  # the replication-group API, even for a single node.
  num_cache_clusters = 1

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [var.redis_security_group_id]

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.redis.arn
  transit_encryption_enabled = true
  # No `auth_token`: configuring one would require Terraform to hold the
  # plaintext (there is no RDS-style `manage_master_user_password` equivalent
  # for ElastiCache AUTH on this provider version), putting a real credential
  # in state — exactly what this baseline avoids everywhere else. Network-
  # level isolation (the security-group-scoped, private-subnet-only ingress
  # above) is this store's access control instead, matching exactly what
  # plan.md names for Redis ("encryption in-transit + at-rest, not public")
  # without adding an unstated AUTH-token requirement. Documented judgment
  # call (Checkov CKV_AWS_31 waived — see the progress notes), flagged for
  # security's review.

  automatic_failover_enabled = false
  # Single-node, no automatic failover (Checkov CKV2_AWS_50 waived) — matches
  # this run's explicit data-security-baseline scope (compute-topology/
  # production-scale HA sizing deferred, plan.md Stack notes); see the
  # progress notes for the full waiver reasoning.

  tags = var.tags
}
