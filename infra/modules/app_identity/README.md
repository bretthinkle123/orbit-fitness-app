# infra/modules/app_identity/

## Purpose

The Lambda execution role (`aws_iam_role.this`, named `<name_prefix>-task`, trusting
`lambda.amazonaws.com`) shared by the production root and `infra/envs/local`, so there is
one trust policy. The function itself is A2's and will attach to this role.

## Modules

`main.tf` (the role), `variables.tf` (`name_prefix`, `tags`), `outputs.tf` (`role_name`, `role_arn`).

## How they relate

`modules/secrets` and `modules/observability` attach their policies to `role_name`.
