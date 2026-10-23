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
  (
    context.idc.groups has "11111111-1111-1111-1111-111111111111" ||
    context.idc.groups has "d242c5b0-6081-1845-6fa8-6e0d9513c107"
  )
};
