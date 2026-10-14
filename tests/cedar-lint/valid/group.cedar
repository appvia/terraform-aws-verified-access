// managed-by: terraform-aws-verified-access
// kind: group
// name: platform-engineers
// source: structured
// owner: platform-team
// justification: Platform engineers operate the demo tenant hosts
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  context.idc.user.email.verified == true &&
  (
    context.idc.groups has "c242c5b0-6081-1845-6fa8-6e0d9513c107" ||
    context.idc.groups has "d242c5b0-6081-1845-6fa8-6e0d9513c107"
  )
};
