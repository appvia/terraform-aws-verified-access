locals {
  ## The tags applied to all resources
  tags = merge(var.tags, {})
  ## Indicates a device trust provider is configured
  enable_device_trust = var.device_trust_provider != null
  ## The Cedar context key for the user trust provider, shared by the trust provider and the rendered policies
  user_policy_reference = var.user_trust_provider.policy_reference_name
  ## The Cedar context key for the device trust provider, defaults to the provider type
  device_policy_reference = local.enable_device_trust ? coalesce(var.device_trust_provider.policy_reference_name, var.device_trust_provider.type) : ""
  ## All endpoints keyed by endpoint name, annotated with the group they belong to
  endpoints = merge([
    for group_name, group in var.groups : {
      for name, endpoint in group.endpoints : name => merge(endpoint, { group = group_name })
    }
  ]...)
}
