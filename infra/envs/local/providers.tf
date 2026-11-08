# Guard layers against ever touching real AWS (AC8), each claimed only as far as
# T1's probes proved it:
#   Layer A - every service endpoint is pinned to var.moto_endpoint (validated to
#             loopback) and the credentials are static, so ambient AWS_* variables
#             and profiles are never consulted.
#   Layer B - allowed_account_ids makes the provider compare the account moto's STS
#             reports with 123456789012. skip_credentials_validation and
#             skip_requesting_account_id are deliberately left unset so that
#             comparison actually runs.
provider "aws" {
  region = var.aws_region

  # Moto dummies, never real credentials. Static values take precedence over the
  # AWS_ACCESS_KEY_ID / AWS_PROFILE chain, which is what keeps a developer's real
  # credentials out of this root.
  #checkov:skip=CKV_AWS_41:static dummy credentials for the local moto emulator; they are not valid against real AWS
  access_key = "test"
  secret_key = "test"

  # No EC2 metadata service on a laptop; without this the provider waits on it.
  skip_metadata_api_check = true
  # Moto serves S3 on a single host, so bucket-in-hostname addressing cannot work.
  s3_use_path_style = true

  allowed_account_ids = [var.aws_account_id]

  endpoints {
    secretsmanager = var.moto_endpoint
    ssm            = var.moto_endpoint
    kms            = var.moto_endpoint
    logs           = var.moto_endpoint
    iam            = var.moto_endpoint
    s3             = var.moto_endpoint
    sns            = var.moto_endpoint
    dynamodb       = var.moto_endpoint
    sts            = var.moto_endpoint
  }

  default_tags {
    tags = local.common_tags
  }
}
