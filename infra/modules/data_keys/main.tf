# Data keys module - the customer-managed KMS keys (and aliases + key policies)
# for RDS storage encryption and ElastiCache Redis at-rest encryption. Split out of
# modules/data so infra/envs/local can create the keys against moto while RDS and
# ElastiCache themselves are compose containers locally (plan.md "module split,
# never fork"). modules/data takes the key ARNs as inputs.

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
