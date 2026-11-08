# Remote state on moto's S3 (the bucket is created by `local_aws.py ensure-state-backend`).
# Locking uses S3 conditional writes (`use_lockfile`); there is deliberately no
# `dynamodb_table`, which Terraform deprecates and nothing else in A1 needs.
bucket       = "orbit-local-tfstate"
key          = "envs/local/terraform.tfstate"
region       = "us-east-1"
use_lockfile = true
encrypt      = true

endpoints = {
  s3 = "http://localhost:5001"
}
use_path_style = true

# These are the backend's own switches, independent of the provider block: the backend
# has no STS override here, and moto is the only thing it can reach.
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_region_validation      = true

# Moto dummies, never real credentials.
access_key = "test"
secret_key = "test"
