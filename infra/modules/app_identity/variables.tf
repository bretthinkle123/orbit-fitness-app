variable "name_prefix" {
  description = "Resource name prefix; the role is named `<name_prefix>-task`."
  type        = string
}

variable "tags" {
  type = map(string)
}
