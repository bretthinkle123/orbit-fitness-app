# Network module — VPC + private-only data-tier subnets + the security
# groups that enforce "no 0.0.0.0/0 ingress" for the DB/Redis (plan.md
# §Infrastructure; baseline.md "Network exposure"). No compute/public
# subnets this run (data-security baseline only).

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = "${var.aws_region}${var.availability_zone_suffixes[count.index]}"

  # `map_public_ip_on_launch` defaults false — these subnets carry only the
  # private data tier (RDS/ElastiCache). "Not publicly accessible" (AC20)
  # starts at the network layer, not just each resource's own flag.
  tags = merge(var.tags, { Name = "${var.name_prefix}-private-${count.index}" })
}

# The future app-tier's security group. Compute topology itself is deferred
# (plan.md Stack notes) — this group exists now purely so the DB/Redis
# security groups below have a concrete principal to scope their ingress to;
# a later compute-topology run attaches real compute to this SAME group
# rather than replacing it.
#
# Checkov waivers on all three security groups below (documented here once,
# applies to all): CKV_AWS_382 ("no egress to 0.0.0.0/0 on all ports") is
# waived — plan.md names only INGRESS restriction as the requirement
# (baseline.md marks that half critical; egress is not), and narrowing
# egress precisely needs a NAT/VPC-endpoint topology this data-security
# baseline deliberately defers (plan.md Stack notes). CKV2_AWS_5 ("security
# group attached to another resource") is waived for `app` — no compute
# exists to attach it to yet, by design; it is NOT waived in spirit for `db`/
# `redis`, which genuinely are referenced by `aws_db_instance`/
# `aws_elasticache_replication_group` below (Checkov's specific check just
# doesn't recognize that style of attachment).
resource "aws_security_group" "app" {
  #checkov:skip=CKV_AWS_382:egress-to-0.0.0.0/0 waived - plan.md names only INGRESS restriction as the requirement; narrowing egress precisely needs a NAT/VPC-endpoint topology this data-security baseline deliberately defers (plan.md Stack notes)
  #checkov:skip=CKV2_AWS_5:no compute exists to attach this future app-tier group to yet, by design - a later compute-topology run attaches real compute to this SAME group rather than replacing it
  name        = "${var.name_prefix}-app"
  description = "Future app-tier security group - DB/Redis ingress is scoped to exactly this group, never 0.0.0.0/0."
  vpc_id      = aws_vpc.main.id

  # AWS restricts SG rule descriptions to a plain-ASCII charset (no em-dash,
  # section marks, etc.) - discovered via a real `terraform plan` failure,
  # not assumed; every description in this file is plain ASCII as a result.
  egress {
    description = "Outbound to the internet (Firebase, Secrets Manager, etc.) - narrowing this further (NAT vs VPC endpoints) is a compute-topology-stage decision, not part of this data-security baseline."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-sg" })
}

resource "aws_security_group" "db" {
  #checkov:skip=CKV_AWS_382:egress-to-0.0.0.0/0 waived - same rationale as the app security group above (plan.md names only INGRESS restriction; egress narrowing is a compute-topology-stage decision)
  #checkov:skip=CKV2_AWS_5:genuinely referenced by aws_db_instance.postgres's vpc_security_group_ids below - Checkov's specific check just doesn't recognize that style of attachment
  name        = "${var.name_prefix}-db"
  description = "RDS ingress restricted to the app security group on 5432 ONLY - no 0.0.0.0/0 (plan.md Infrastructure section, Checkov-enforced)."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from the app tier only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Default outbound - a database has no inbound-triggered egress need beyond replies, kept open rather than hand-listing ephemeral return ports."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-sg" })
}

resource "aws_security_group" "redis" {
  #checkov:skip=CKV_AWS_382:egress-to-0.0.0.0/0 waived - same rationale as the app/db security groups above (plan.md names only INGRESS restriction; egress narrowing is a compute-topology-stage decision)
  #checkov:skip=CKV2_AWS_5:genuinely referenced by aws_elasticache_replication_group.redis's security_group_ids below - Checkov's specific check just doesn't recognize that style of attachment
  name        = "${var.name_prefix}-redis"
  description = "ElastiCache ingress restricted to the app security group on 6379 ONLY - the same no-0.0.0.0/0 posture as the DB security group."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from the app tier only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Default outbound - a cache has no inbound-triggered egress need beyond replies, kept open rather than hand-listing ephemeral return ports."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-redis-sg" })
}

# Checkov CKV2_AWS_12: every VPC's auto-created default security group must
# deny all traffic - nothing should ever attach to it (real traffic is
# scoped through the purpose-built app/db/redis groups above instead).
resource "aws_default_security_group" "locked_down" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-default-locked-down" })
}

# VPC flow logs (baseline.md "Network exposure": "VPC flow logs / resource-
# level logging enabled") - not explicitly named in plan.md's Infrastructure
# section, but cheap, standard network-visibility hardening consistent with
# this baseline's overall posture; added rather than waived. Retention is
# 400 days (Checkov CKV_AWS_338 wants >=365) - unlike the app/audit log
# groups, plan.md does not mandate a specific retention figure for flow-log
# metadata, so there is no reason to keep it at 90 days too.
#
# No KMS key on this log group (Checkov CKV_AWS_158 waived): flow-log
# metadata (source/dest IP, port, byte counts) is lower-sensitivity network
# telemetry, not personal/regulated data - already encrypted at rest by
# AWS's own default CloudWatch Logs encryption; a fifth customer-managed key
# just for this one add-on group is not worth the added complexity this run.
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  #checkov:skip=CKV_AWS_158:flow-log metadata (source/dest IP, port, byte counts) is lower-sensitivity network telemetry, not personal/regulated data - already encrypted at rest by AWS's own default CloudWatch Logs encryption; a fifth customer-managed key just for this one add-on group is not worth the added complexity this run
  name              = "/${var.name_prefix}/vpc-flow-logs"
  retention_in_days = 400
  tags              = var.tags
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.name_prefix}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

data "aws_iam_policy_document" "vpc_flow_logs_write" {
  statement {
    sid    = "WriteVpcFlowLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs_write" {
  name   = "${var.name_prefix}-vpc-flow-logs-write"
  role   = aws_iam_role.vpc_flow_logs.name
  policy = data.aws_iam_policy_document.vpc_flow_logs_write.json
}

resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc-flow-log" })
}
