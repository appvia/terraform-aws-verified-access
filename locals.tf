locals {
  ## The tags applied to all resources
  tags = merge(var.tags, {})
  ## The base name of all resources, <name_prefix>-<name>, following the caller's naming convention
  resource_name = format("%s-%s", var.name_prefix, var.name)
  ## The length of the hash naming target groups, <name_prefix>-<hash>, within the 32 character limit
  target_group_hash_length = min(16, 31 - length(var.name_prefix))
  ## Indicates the module adds its groups and endpoints to an existing instance, rather than creating the instance,
  ## its trust providers and its logging
  enable_existing_instance = var.existing_instance != null
  ## Indicates the module creates the instance
  enable_instance = !local.enable_existing_instance
  ## The id of the instance holding the groups and endpoints: the created one, or the existing one
  instance_id = local.enable_instance ? aws_verifiedaccess_instance.current[0].id : var.existing_instance.id
  ## The type of the user trust provider the policies are rendered for: the created one, or the one attached to the
  ## existing instance
  user_trust_provider_type = local.enable_instance ? try(var.user_trust_provider.type, null) : var.existing_instance.user_trust_provider_type
  ## The device trust provider the policies are rendered for, normalised: the created one, or the one attached to the
  ## existing instance; null when none
  device_trust_provider = local.enable_existing_instance ? var.existing_instance.device_trust_provider : (
    var.device_trust_provider == null ? null : {
      type                  = var.device_trust_provider.type
      policy_reference_name = var.device_trust_provider.policy_reference_name
      crowdstrike_min_score = var.device_trust_provider.crowdstrike_min_score
      jamf_allowed_risk     = var.device_trust_provider.jamf_allowed_risk
    }
  )
  ## Indicates a device trust provider is in use, so sensitive endpoints render a device condition
  enable_device_trust = local.device_trust_provider != null
  ## Indicates the module creates the device trust provider
  enable_device_trust_provider = local.enable_instance && var.device_trust_provider != null
  ## The Cedar context key for the user trust provider, shared by the trust provider and the rendered policies
  user_policy_reference = local.enable_instance ? try(var.user_trust_provider.policy_reference_name, "") : var.existing_instance.user_policy_reference_name
  ## The Cedar context key for the device trust provider, defaults to the provider type
  device_policy_reference = local.enable_device_trust ? coalesce(local.device_trust_provider.policy_reference_name, local.device_trust_provider.type) : ""
  ## The attribute of the user context holding the groups: the configured OIDC claim, or groups for Identity Center
  user_groups_attribute = local.user_trust_provider_type != "oidc" ? "groups" : (
    local.enable_instance ? var.user_trust_provider.oidc.groups_claim : var.existing_instance.user_groups_claim
  )
  ## The key encrypting the trust providers, groups and endpoints: the created one, the supplied one, or none
  kms_key_arn = var.create_kms_key ? aws_kms_key.current[0].arn : var.kms_key_arn
  ## All endpoints keyed by endpoint name, annotated with the group they belong to, with their tags merged over the
  ## module and group tags
  endpoints = merge([
    for group_name, group in var.groups : {
      for name, endpoint in group.endpoints : name => merge(endpoint, {
        group = group_name
        tags  = merge(local.tags, group.tags, endpoint.tags)
      })
    }
  ]...)
  ## The resolved targets of each endpoint: endpoints with targets use the central load balancer (referenced through
  ## their listener, so it exists first), connect to it on their listener port and send only to the module subnets;
  ## http and https endpoints without their own certificate use the module certificate
  endpoint_targets = {
    for name, endpoint in local.endpoints : name => {
      port = contains(keys(local.load_balancer_endpoints), name) && endpoint.protocol != "tcp" ? local.load_balancer_endpoints[name].listener_port : endpoint.port
      port_ranges = contains(keys(local.load_balancer_endpoints), name) && endpoint.protocol == "tcp" ? [
        { from_port = local.load_balancer_endpoints[name].listener_port, to_port = local.load_balancer_endpoints[name].listener_port }
      ] : endpoint.port_ranges
      domain_certificate_arn = endpoint.domain_certificate_arn != null || endpoint.application_domain == null ? endpoint.domain_certificate_arn : local.certificate_arn
      egress_cidr_blocks = coalesce(
        endpoint.egress_cidr_blocks,
        contains(keys(local.load_balancer_endpoints), name) ? local.load_balancer_cidr_blocks : var.allowed_egress_cidr_blocks,
      )
      load_balancer_arn = contains(keys(local.load_balancer_endpoints), name) ? aws_lb_listener.current[name].load_balancer_arn : endpoint.load_balancer_arn
    }
  }
}
