# `infra/` — Terraform (AWS)

> Per-directory README — diff, don't rewrite on later changes.

## Purpose

Provisions the **data-security baseline** for Orbit on AWS: persistence, secrets,
observability, and network isolation. This run deliberately **defers the compute
topology** (App Runner/ECS + ALB + autoscaling + the `envs/` staging/prod split + WAF)
to the deployment stage — see `docs/system_architecture.md` §Deployment topology and
`plans/01-production-deploy-path.md`. The backend runs as a direct process this run
(CLAUDE.md), reading secrets from Secrets Manager/SSM in deploy.

## Modules

| File / dir | Responsibility |
|---|---|
| `backend.tf` / `backend.hcl.example` / `backend.tf.template` | Remote-state wiring. `backend.tf` deliberately declares no backend block yet (implicit local backend) so `terraform init -backend=false` + `plan` succeed without live AWS credentials on this host; `backend.tf.template` holds the real S3 (SSE) + DynamoDB-lock target for when an AWS account exists. |
| `main.tf` | AWS provider (exact-pinned `hashicorp/aws`, source hand-verified against the registry), tagging, module composition. |
| `variables.tf` / `outputs.tf` | Root-level inputs (incl. `offline_validate`, the credential-less-plan flag) and outputs. |
| `modules/network/` | VPC + private subnets + security groups — DB/Redis ingress restricted to the app security group only, never `0.0.0.0/0`. |
| `modules/data/` | `aws_db_instance.postgres` (RDS PostgreSQL: `storage_encrypted`, KMS CMK, not publicly accessible, multi-AZ, 7-day backups, `rds.force_ssl`) + `aws_elasticache_replication_group.redis` (rate-limit store: at-rest + in-transit encryption). |
| `modules/secrets/` | Secrets Manager (DB URL, Firebase Admin service-account JSON) + SSM Parameter Store (non-secret config); least-privilege read policy for the app task role. |
| `modules/observability/` | CloudWatch app + audit log groups (retention + a resource policy denying `logs:Delete*`/`PutRetentionPolicy` to all but an ops role); X-Ray write permission. |

## Relationships

The root module composes the four child modules; nothing reaches around the root
(`iac-conventions` facade discipline). `modules/secrets` and `modules/observability`
feed the identifiers the backend's `src/orbit/config/secrets.py` and
`src/orbit/logging/`/`observability/` facades resolve at runtime. `modules/data`'s
security group only accepts traffic from the (not-yet-provisioned) app security group —
there is no compute here to attach it to yet.

## Notes

- Validated with `infra-validate.sh` (`fmt -check` / `validate` / `plan` →
  `.pipeline/infra-plan.txt`) on every smoke check; Checkov scans `infra/` in security
  (166 passed / 0 failed / 26 documented skips this run).
- Egress on the `db`/`redis` security groups is intentionally left unrestricted for now
  (Trivy `AWS-0104`, accepted risk — see `.trivyignore` and
  `.pipeline/security-report.md`): narrowing it needs a NAT/VPC-endpoint topology that
  doesn't exist until compute lands.
- `terraform apply` never runs in this pipeline — only in CI (`deploy.yml`), after
  merge, and only once `DEPLOY_ENABLED` is set.
