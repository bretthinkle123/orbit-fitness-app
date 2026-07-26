# Observability module — the app + audit CloudWatch log groups, the
# delete-deny resource policy that makes the audit trail immutable, and the
# task role's write (never delete) permissions (plan.md §Logging /
# §Infrastructure; STRIDE Repudiation row).

# Explicit key policy (Checkov CKV2_AWS_64) granting root full access PLUS
# the CloudWatch Logs service principal the specific actions it needs to
# encrypt/decrypt log data with this CMK (Checkov CKV_AWS_158) — without this
# second statement, CloudWatch Logs could never write to a KMS-encrypted log
# group at all. `var.aws_account_id`/`var.aws_region` are plain variables,
# never a live `aws_caller_identity`/`aws_region` data-source lookup (root
# variables.tf — avoids breaking credential-less `terraform plan`).
data "aws_iam_policy_document" "logs_kms_key_policy" {
  # Waiver: Checkov's CKV_AWS_356/111/109 flag the "kms:*"/Resource:"*"
  # root-account statement below as an overly-broad IAM grant - AWS's OWN
  # standard KMS key-policy baseline (same reasoning as modules/data's and
  # modules/secrets' KMS key policies), waived rather than "fixed." These
  # must stay INSIDE the block body - checkov 3.3.8 does not honor a skip
  # comment placed above a data/resource declaration (verified empirically).
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

  statement {
    sid    = "AllowCloudWatchLogsToUseTheKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "logs" {
  description         = "CMK for the app + audit CloudWatch log groups (${var.name_prefix})."
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.logs_kms_key_policy.json
  tags                = var.tags
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

# Retention is 90 days (`var.log_retention_days`'s default) — a deliberate,
# plan-mandated figure (plan.md §Logging: "retention 90 d"), not an
# oversight. Checkov's generic best-practice check (CKV_AWS_338) wants >=365
# days; overriding to a year here would contradict the approved plan/
# acceptance criteria, so this is a documented waiver, not a fix.
resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_338:90d retention is a deliberate, plan-mandated figure (plan.md Logging: "retention 90 d"), not an oversight - overriding to Checkov's >=365d best-practice default would contradict the approved plan/acceptance criteria
  name              = "/${var.name_prefix}/app"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "audit" {
  #checkov:skip=CKV_AWS_338:same 90d plan-mandated retention rationale as the app log group above
  name              = "/${var.name_prefix}/audit"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  tags              = var.tags
}

# Immutability (plan.md §Logging "enabling condition"): deny delete/
# retention-change on EITHER log group to every principal except the
# dedicated ops role. The app's own task role is never in the exception
# list — it may WRITE, never delete or shorten retention (Repudiation
# defense, ASVS 16.2.1/16.3.x/16.4.1).
data "aws_iam_policy_document" "log_delete_deny" {
  statement {
    sid    = "DenyLogGroupDeletionExceptOps"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:PutRetentionPolicy",
    ]

    resources = [
      aws_cloudwatch_log_group.app.arn,
      aws_cloudwatch_log_group.audit.arn,
      "${aws_cloudwatch_log_group.app.arn}:*",
      "${aws_cloudwatch_log_group.audit.arn}:*",
    ]

    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = [var.ops_role_arn]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "delete_deny" {
  policy_name     = "${var.name_prefix}-log-delete-deny"
  policy_document = data.aws_iam_policy_document.log_delete_deny.json
}

# The app task role may WRITE to its own two log groups — nothing more (it
# never appears in the delete-deny exception above).
data "aws_iam_policy_document" "app_log_write" {
  statement {
    sid    = "WriteOrbitLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.app.arn}:*",
      "${aws_cloudwatch_log_group.audit.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "app_log_write" {
  name   = "${var.name_prefix}-log-write"
  role   = var.app_task_role_name
  policy = data.aws_iam_policy_document.app_log_write.json
}

# X-Ray write permission for the task role (plan.md §Infrastructure) — the
# AWS-managed policy is exactly the write-only action set X-Ray tracing
# needs, avoiding a hand-rolled action list that could drift from the real
# API surface.
resource "aws_iam_role_policy_attachment" "app_xray_write" {
  role       = var.app_task_role_name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
