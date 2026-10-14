variable "description" {
  description = "The description of the Verified Access group"
  type        = string
  default     = null
}

variable "instance_id" {
  description = "The id of the Verified Access instance the group belongs to"
  type        = string
}

variable "kms_key_arn" {
  description = "An optional customer managed KMS key used to encrypt the group"
  type        = string
  default     = null
}

variable "name" {
  description = "The name of the Verified Access group"
  type        = string
}

variable "policy_document" {
  description = "The rendered Cedar policy for the group"
  type        = string
}

variable "tags" {
  description = "The tags to apply to all resources"
  type        = map(string)
}
