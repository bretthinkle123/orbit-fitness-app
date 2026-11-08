# Partial configuration: the settings live in backend.moto.hcl and are supplied at init
# (`terraform init -backend-config=backend.moto.hcl`), so this file names no endpoint.
terraform {
  backend "s3" {}
}
