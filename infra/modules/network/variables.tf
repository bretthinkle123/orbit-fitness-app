variable "name_prefix" {
  description = "Naming/tagging prefix, e.g. `orbit-production` (iac-conventions: <service>-<environment>-<resource>)."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource (environment, service, managed-by)."
  type        = map(string)
}

variable "aws_region" {
  description = "AWS region — used only to compute availability-zone NAMES (e.g. \"us-east-1a\") from the suffixes below via plain string interpolation, deliberately NOT via the `aws_availability_zones` data source: that data source requires a live EC2 API call, which would break credential-less `terraform plan` (Operator addendum #4)."
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "One CIDR per private subnet — length must match `availability_zone_suffixes`."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "availability_zone_suffixes" {
  description = "AZ suffixes (e.g. [\"a\",\"b\"]) appended to `var.aws_region` to build each subnet's `availability_zone` — a plain list so this module never needs a live AWS API call to resolve real AZ names."
  type        = list(string)
  default     = ["a", "b"]
}
