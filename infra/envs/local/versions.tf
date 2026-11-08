terraform {
  # 1.11 is the floor for S3-native state locking (`use_lockfile`), staged in T3.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    # Same exact pin as the root so local and prod exercise one provider version.
    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }
  }
}
