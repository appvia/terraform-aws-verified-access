// managed-by: terraform-aws-verified-access
// kind: endpoint
// name: demo-ssh
// source: structured
// sensitive: false
// owner: platform-team
// justification: Platform engineers operate the demo tenant hosts
// user-context: okta
// device-context: crowdstrike
permit(principal, action, resource)
when {
  (
    context.okta.additional_user_context.groups.contains("admins")
  )
};
