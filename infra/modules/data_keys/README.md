# infra/modules/data_keys/

## Purpose

The customer-managed KMS keys, aliases and key policies for RDS storage and ElastiCache Redis
at-rest encryption, split out of `modules/data` so `infra/envs/local` can create them against
moto while RDS and ElastiCache are compose containers locally.

## Modules

`main.tf` (`aws_kms_key` and `aws_kms_alias` for `rds` and `redis`), `variables.tf`
(`name_prefix`, `tags`, `aws_account_id`), `outputs.tf` (`rds_kms_key_arn`, `redis_kms_key_arn`).

## How they relate

`modules/data` takes the two key ARNs as inputs. The Checkov skips in `main.tf` must stay
inside the `data` block body.
