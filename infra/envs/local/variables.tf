variable "moto_endpoint" {
  description = "Base URL of the local moto server every AWS service endpoint is pinned to. The regex admits only loopback or the compose service name, so a real AWS (or any other) URL cannot be supplied."
  type        = string
  default     = "http://localhost:5001"

  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1|moto):[0-9]{2,5}$", var.moto_endpoint))
    error_message = "moto_endpoint must match ^http://(localhost|127.0.0.1|moto):<port>$ - this root only ever talks to a local moto server."
  }
}

variable "aws_region" {
  description = "Region moto emulates."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "Moto's default account id. It equals the root's documented placeholder, so KMS key policies built from it are valid against moto."
  type        = string
  default     = "123456789012"
}
