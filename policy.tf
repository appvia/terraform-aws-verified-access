locals {
  ## The identity group conditions per structured group (group/<name>) and endpoint (endpoint/<name>) policy, sorted
  ## so the same input always renders the same policy. IAM Identity Center keys groups by id (has); OIDC providers
  ## list group names (contains) in the configured groups claim
  identity_group_conditions = {
    for key, ids in merge(
      { for name, group in var.groups : format("group/%s", name) => group.policy.identity_groups if group.policy != null },
      { for name, endpoint in local.endpoints : format("endpoint/%s", name) => endpoint.policy.identity_groups if length(try(endpoint.policy.identity_groups, [])) > 0 },
      ) : key => [
      for id in sort(distinct(ids)) : (
        local.user_trust_provider_type == "iam-identity-center"
        ? format("context.%s.%s has \"%s\"", local.user_policy_reference, local.user_groups_attribute, id)
        : format("context.%s.%s.contains(\"%s\")", local.user_policy_reference, local.user_groups_attribute, id)
      )
    ]
  }

  ## The verified email condition, only available from IAM Identity Center
  email_conditions = local.user_trust_provider_type == "iam-identity-center" && (local.enable_instance ? var.user_trust_provider.require_verified_email : var.existing_instance.require_verified_email) ? [
    format("context.%s.user.email.verified == true", local.user_policy_reference)
  ] : []

  ## The device posture condition applied to sensitive endpoints, specific to each device provider
  device_condition = !local.enable_device_trust ? "" : (
    local.device_trust_provider.type == "crowdstrike" ? format("context.%s.assessment.overall >= %d", local.device_policy_reference, local.device_trust_provider.crowdstrike_min_score) :
    local.device_trust_provider.type == "jamf" ? format("[%s].contains(context.%s.risk)", join(", ", [for risk in sort(distinct(local.device_trust_provider.jamf_allowed_risk)) : format("\"%s\"", risk)]), local.device_policy_reference) :
    format("context.%s.device.is_managed == true", local.device_policy_reference)
  )

  ## The accountable owner and justification of each group, structured or raw
  group_owners         = { for name, group in var.groups : name => trimspace(try(group.policy.owner, group.raw_policy.owner)) }
  group_justifications = { for name, group in var.groups : name => trimspace(try(group.policy.justification, group.raw_policy.justification)) }

  ## The trust provider context lines shared by every policy header
  context_headers = compact([
    format("// user-context: %s", local.user_policy_reference),
    local.enable_device_trust ? format("// device-context: %s", local.device_policy_reference) : "",
  ])

  ## The machine readable header of every group policy, read by reviewers and the Cedar lint
  group_headers = {
    for name, group in var.groups : name => concat([
      "// managed-by: terraform-aws-verified-access",
      "// kind: group",
      format("// name: %s", name),
      format("// source: %s", group.policy != null ? "structured" : "raw"),
      format("// owner: %s", local.group_owners[name]),
      format("// justification: %s", local.group_justifications[name]),
    ], local.context_headers)
  }

  ## The rendered Cedar policy of every group
  group_policies = {
    for name, group in var.groups : name => format("%s\n%s\n", join("\n", local.group_headers[name]), (
      group.policy != null ? join("\n", [
        "permit(principal, action, resource)",
        "when {",
        join(" &&\n", [
          for condition in concat(local.email_conditions, [
            format("(\n    %s\n  )", join(" ||\n    ", local.identity_group_conditions[format("group/%s", name)]))
          ]) : format("  %s", condition)
        ]),
        "};",
      ]) : trimspace(group.raw_policy.cedar)
    ))
  }

  ## The endpoints needing their own policy: structured endpoint policies, sensitive endpoints (device posture) and raw
  ## policies
  policy_endpoints = {
    for name, endpoint in local.endpoints : name => endpoint if endpoint.policy != null || endpoint.raw_policy != null || endpoint.sensitive
  }

  ## The conditions of each structured endpoint policy, combined with AND: its identity groups (any of), its additional
  ## conditions (each parenthesised, so an || inside one cannot widen the others) and, when sensitive, device posture
  endpoint_conditions = {
    for name, endpoint in local.policy_endpoints : name => concat(
      contains(keys(local.identity_group_conditions), format("endpoint/%s", name)) ? [
        format("(\n    %s\n  )", join(" ||\n    ", local.identity_group_conditions[format("endpoint/%s", name)]))
      ] : [],
      [for condition in try(endpoint.policy.additional_conditions, []) : format("(%s)", trimspace(condition))],
      endpoint.sensitive ? [local.device_condition] : [],
    ) if endpoint.raw_policy == null
  }

  ## The machine readable header of every endpoint policy
  endpoint_headers = {
    for name, endpoint in local.policy_endpoints : name => concat([
      "// managed-by: terraform-aws-verified-access",
      "// kind: endpoint",
      format("// name: %s", name),
      format("// source: %s", endpoint.raw_policy != null ? "raw" : "structured"),
      format("// sensitive: %t", endpoint.sensitive),
      format("// owner: %s", endpoint.raw_policy != null ? trimspace(endpoint.raw_policy.owner) : try(trimspace(endpoint.policy.owner), local.group_owners[endpoint.group])),
      format("// justification: %s", endpoint.raw_policy != null ? trimspace(endpoint.raw_policy.justification) : try(trimspace(endpoint.policy.justification), local.group_justifications[endpoint.group])),
    ], local.context_headers)
  }

  ## The rendered Cedar policy of endpoints that need one, evaluated in addition to the group policy
  endpoint_policies = {
    for name, endpoint in local.policy_endpoints : name => format("%s\n%s\n", join("\n", local.endpoint_headers[name]), (
      endpoint.raw_policy != null ? trimspace(endpoint.raw_policy.cedar) : join("\n", [
        "permit(principal, action, resource)",
        "when {",
        join(" &&\n", [for condition in local.endpoint_conditions[name] : format("  %s", condition)]),
        "};",
      ])
    ))
  }
}
