# App identity module — the Lambda execution role the secrets and observability
# modules attach their least-privilege policies to. Extracted from the root so
# infra/ and infra/envs/local share one trust policy instead of two copies that
# drift (plan.md "Terraform infra/envs/local/" § module changes, item 3).
#
# The function itself is deferred to A2, which attaches it to this same role
# rather than creating a second one.
resource "aws_iam_role" "this" {
  name = "${var.name_prefix}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}
