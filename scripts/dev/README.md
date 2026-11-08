# scripts/dev/

## Purpose

Python ops tooling for the local stack, run from the venv by `scripts/dev-up.sh`. It is not
part of the app package (`src/orbit/`).

## Modules

| File | Role |
|---|---|
| `local_aws.py` | argparse CLI with subcommands `validate-env`, `ensure-state-backend`, `seed-secrets`. Checks `.env.local` against its contract, creates the moto Terraform-state bucket, writes the `orbit/database-url` secret into moto. `ensure-state-backend --report` prints exactly `state_bucket_created=1` or `=0` on stdout (summary on stderr); `dev-up.sh` reads that line to detect a moto reset. Every subcommand first requires a loopback `AWS_ENDPOINT_URL` |
| `__init__.py` | Package marker |

## How they relate

`scripts/dev-up.sh` calls `local_aws.py` before and after `terraform apply` in
`infra/envs/local`. Tests: `tests/unit/test_dev_scripts.py`. See `docs/local-development.md`.
