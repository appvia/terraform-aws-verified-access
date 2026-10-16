variable "alarm_email_addresses" {
  description = "The email addresses notified by the alarms; each recipient must confirm the subscription"
  type        = list(string)
  default     = []
}

variable "identity_group_ids" {
  description = "The IAM Identity Center group ids permitted to reach the target"
  type        = list(string)
}
