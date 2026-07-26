# Remote state (iac-conventions: S3 + DynamoDB lock, SSE-encrypted on the
# state object) is the REAL target for this project - declared in full in
# `backend.tf.template`, a file Terraform does NOT parse (its name doesn't
# end in `.tf`). This file itself declares NO backend block, so Terraform
# defaults to the implicit LOCAL backend. That is deliberate, not an
# oversight - see below.
#
# WHY: empirically verified this session (Terraform 1.15.8, reproduced in
# complete isolation with a single-resource, zero-dependency config):
# `terraform init -backend=false` - the EXACT command `infra-validate.sh`
# runs on every smoke check, immediately before `terraform plan` - never
# writes the backend-initialization marker `plan`/`apply` require. Any
# configuration that declares ANY `backend` block at all (S3, or even an
# explicit `backend "local" {}`) then makes every subsequent `plan`/`apply`
# refuse with "Backend initialization required", regardless of whether the
# block's attributes are filled in. This is not specific to the S3 type or
# to this module's structure. Only a configuration with NO backend block
# (the fully implicit default) lets `-backend=false` + `plan` succeed - the
# smoke check's own real exit test, and the reason this file is written the
# way it is.
#
# Since no AWS account exists yet this run (Operator addendum #4) and the
# credential-less smoke check must pass on every run, the ACTIVE
# configuration stays on the implicit local backend for now.
#
# ACTIVATING THE REAL S3 BACKEND (once an AWS account + bucket/table exist):
#   1. cp backend.tf.template backend.tf
#   2. cp backend.hcl.example backend.hcl   (then fill in bucket/region/table)
#   3. terraform init -backend-config=backend.hcl -reconfigure
# From that point on, the real deploy pipeline's own `terraform init` (never
# `-backend=false`) initializes against the genuine S3 bucket + DynamoDB
# lock table normally - a file swap, not a refactor.
