locals {
  ## The tags applied to all resources
  tags = merge(var.tags, {})
  ## The base name of all resources, <name_prefix>-<name>, following the caller's naming convention
  resource_name = format("%s-%s", var.name_prefix, var.name)
  ## The length of the hash naming target groups, <name_prefix>-<hash>, within the 32 character limit
  target_group_hash_length = min(16, 31 - length(var.name_prefix))
  ## Indicates a device trust provider is configured
  enable_device_trust = var.device_trust_provider != null
  ## The Cedar context key for the user trust provider, shared by the trust provider and the rendered policies
  user_policy_reference = var.user_trust_provider.policy_reference_name
  ## The Cedar context key for the device trust provider, defaults to the provider type
  device_policy_reference = local.enable_device_trust ? coalesce(var.device_trust_provider.policy_reference_name, var.device_trust_provider.type) : ""
  ## The attribute of the user context holding the groups: the configured OIDC claim, or groups for Identity Center
  user_groups_attribute = var.user_trust_provider.type == "oidc" ? var.user_trust_provider.oidc.groups_claim : "groups"
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
