# Secrets module — Secrets Manager containers for the DB URL + Firebase Admin
# service-account JSON, SSM Parameter Store for non-secret config, and the
# least-privilege read policy scoped to exactly these (plan.md
# §Infrastructure; AC22; `src/orbit/config/secrets.py` is the app-side facade
# that fetches these two secret names at runtime).

# Explicit key policy (Checkov CKV2_AWS_64) — functionally identical to
# AWS's own implicit default policy (root account full access), written out
# so Checkov can verify it rather than infer it. `var.aws_account_id` is a
# plain variable, never a live `aws_caller_identity` lookup (root
# variables.tf — avoids breaking credential-less `terraform plan`).
#
# Waiver: Checkov's CKV_AWS_356/111/109 flag the `"kms:*"` / `Resource: "*"`
# root-account statement below as an overly-broad IAM grant. That exact
# statement is AWS's OWN standard, documented KMS key-policy baseline (the
# "Enable IAM User Permissions" statement every AWS-managed default key
# already carries implicitly) — a known false-positive class for KMS
# root-account statements specifically. Narrowing root's own access to its
# own key would be an account-lockout/availability risk, not a security
# improvement, so this is waived rather than "fixed" (same reasoning as
# modules/data's two KMS key policies). The `#checkov:skip` lines must stay
# INSIDE the `data` block body — checkov 3.3.8 does not honor a skip comment
# placed above a `data`/`resource` declaration (verified empirically).
data "aws_iam_policy_document" "secrets_kms_key_policy" {
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

resource "aws_kms_key" "secrets" {
  description         = "CMK for Secrets Manager secrets (${var.name_prefix})."
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.secrets_kms_key_policy.json
  tags                = var.tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# No `aws_secretsmanager_secret_rotation` on either secret below (Checkov
# CKV2_AWS_57 waived on both): real rotation needs a Lambda rotation
# function (compute + its own VPC networking to reach the DB) — out of
# scope for this data-security baseline (compute topology deferred, plan.md
# Stack notes). The containers are provisioned now so the real deploy
# pipeline can populate them, and later wire rotation, with no refactor.
resource "aws_secretsmanager_secret" "database_url" {
  #checkov:skip=CKV2_AWS_57:automatic rotation needs a Lambda rotation function with its own VPC networking to reach the DB - out of scope for this data-security baseline (compute topology deferred, plan.md Stack notes); the container is provisioned now so the real deploy pipeline can wire rotation later with no refactor
  name       = "orbit/database-url"
  kms_key_id = aws_kms_key.secrets.arn
  tags       = var.tags
}

# Deliberately a PLACEHOLDER, never the real DSN: composing the real value
# needs the RDS-managed master password (`modules/data`'s own comment —
# Terraform never reads that plaintext), so the deploy pipeline writes the
# actual connection string here POST-provision, out of band. `ignore_changes`
# protects that pipeline-written value from being clobbered back to this
# placeholder on a later `terraform apply`.
resource "aws_secretsmanager_secret_version" "database_url_placeholder" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "NOT-YET-PROVISIONED -- the deploy pipeline writes the real DSN here post-RDS-provision, never Terraform"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "firebase_admin_credentials" {
  #checkov:skip=CKV2_AWS_57:same rotation-deferred rationale as database_url above
  name       = "orbit/firebase-admin-credentials"
  kms_key_id = aws_kms_key.secrets.arn
  tags       = var.tags
}

# Same placeholder rationale as `database_url` above — the real Firebase
# Admin service-account JSON is uploaded by the operator out of band.
resource "aws_secretsmanager_secret_version" "firebase_admin_credentials_placeholder" {
  secret_id     = aws_secretsmanager_secret.firebase_admin_credentials.id
  secret_string = "NOT-YET-PROVISIONED -- the operator uploads the real Firebase Admin service-account JSON here out of band, never Terraform"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Non-secret config via SSM Parameter Store (plan.md §Infrastructure: "SSM
# Parameter Store for non-secret config"). `SecureString` + the same CMK as
# the two secrets above (Checkov CKV2_AWS_34) — encrypting it costs nothing
# even though the value itself isn't sensitive, so there is no reason not to.
resource "aws_ssm_parameter" "release_version" {
  name   = "/${var.name_prefix}/release-version"
  type   = "SecureString"
  key_id = aws_kms_key.secrets.arn
  value  = "0.1.0"
  tags   = var.tags
}

# Least-privilege read policy for the app task role — scoped to EXACTLY
# these three resources, never a wildcard (baseline.md "Identity & access";
# ASVS 13.2.2).
data "aws_iam_policy_document" "app_secrets_read" {
  statement {
    sid    = "ReadOrbitSecrets"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.database_url.arn,
      aws_secretsmanager_secret.firebase_admin_credentials.arn,
    ]
  }

  statement {
    sid    = "ReadOrbitConfigParameter"
    effect = "Allow"

    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.release_version.arn]
  }

  statement {
    sid    = "DecryptOrbitSecrets"
    effect = "Allow"

    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.secrets.arn]
  }
}

resource "aws_iam_role_policy" "app_secrets_read" {
  name   = "${var.name_prefix}-secrets-read"
  role   = var.app_task_role_name
  policy = data.aws_iam_policy_document.app_secrets_read.json
}
