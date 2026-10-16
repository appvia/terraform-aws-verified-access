// managed-by: terraform-aws-verified-access
// kind: endpoint
// name: demo-db
// source: structured
// sensitive: false
// owner: platform-team
// justification: Platform engineers operate the demo tenant hosts
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  (
    context.idc.groups has "11111111-1111-1111-1111-111111111111"
  )
};
