
## Provision the Verified Access group and attach its Cedar policy
resource "aws_verifiedaccess_group" "current" {
  description                = var.description
  policy_document            = var.policy_document
  tags                       = merge(var.tags, { Name = var.name })
  verifiedaccess_instance_id = var.instance_id

  dynamic "sse_configuration" {
    for_each = var.kms_key_arn != null ? [true] : []

    content {
      customer_managed_key_enabled = true
      kms_key_arn                  = var.kms_key_arn
    }
  }
}
