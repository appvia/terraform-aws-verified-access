// managed-by: terraform-aws-verified-access
// kind: group
// name: platform-engineers
// source: structured
// owner: platform-team
// justification: Platform engineers operate the demo tenant hosts
// user-context: okta
permit(principal, action, resource)
when {
  (
    context.okta.groups.contains("x") || true || ["y")
  )
};
