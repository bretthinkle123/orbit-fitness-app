# `infra/envs/local/` — Terraform root for the local stack (moto)

> Per-directory README — diff, don't rewrite on later changes.

## Purpose

Applies the same modules as `infra/` to a **moto** server on the developer's machine, so the
Terraform in this repo is exercised end to end without an AWS account. It is local-only and
can never reach real AWS (the guards are described below). Run by `scripts/dev-up.sh` and by
CI's `local-stack` job.

## Modules

| File | Responsibility |
|---|---|
| `versions.tf` | Terraform `>= 1.11.0, < 2.0.0` (S3-native locking needs 1.11); `hashicorp/aws` exactly 6.52.0, the same pin as the root. |
| `providers.tf` | One `aws` provider pinned to moto: all nine endpoints from `var.moto_endpoint`, static dummy credentials, `allowed_account_ids`, path-style S3. |
| `variables.tf` | `moto_endpoint` (validated to loopback or the `moto` service name), `aws_region`, `aws_account_id` (moto's default `123456789012`). |
| `main.tf` | Composes `app_identity`, `secrets` (with `recovery_window_in_days = 0`), `observability` and `data_keys`. **Not** `data` (RDS and ElastiCache are compose containers) and **not** `network` (no local equivalent). |
| `outputs.tf` | Secret ARNs, log group names, key ARNs, the app role ARN. |
| `backend.tf` / `backend.moto.hcl` | Partial S3 backend on moto with `use_lockfile = true` and no `dynamodb_table`; settings are passed at `init`. |
| `.terraform.lock.hcl` | Provider lock for darwin_arm64 and linux_amd64. |

## Relationships

`scripts/dev/local_aws.py ensure-state-backend` creates the one state bucket before
`terraform init -backend-config=backend.moto.hcl` (Terraform cannot create its own backend).
`scripts/dev/local_aws.py seed-secrets` writes the real database DSN into the secret this root
creates, out of band, so the password never enters Terraform state.

## Notes

- **Guard layers:** (A) endpoints pinned to a validated loopback URL and static credentials,
  proven by probes (regex; probe 2 with fake ambient keys plus an existing scratch profile;
  probe 2-neg with a nonexistent profile, which must fail closed); (B) `allowed_account_ids`,
  proven by probe 1 (a mismatched id makes `plan` fail). Probe `*_override.tf` files are
  gitignored.
- moto is in memory: the state, the lock and the resources vanish together when it restarts, and
  `dev-up.sh` simply rebuilds them.
- Backend `use_lockfile` and why not DynamoDB: `docs/local-development.md`.
