// managed-by: terraform-aws-verified-access
// kind: group
// name: platform-engineers
// source: structured
// owner: platform-team
// justification: Platform engineers operate the demo tenant hosts
// user-context: okta
// device-context: crowdstrike
permit(principal, action, resource)
when {
  (
    context.okta.groups.contains("CORP\\admins") ||
    context.okta.groups.contains("x\") || true || [\"y")
  )
};
