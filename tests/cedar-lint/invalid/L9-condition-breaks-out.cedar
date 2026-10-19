// managed-by: terraform-aws-verified-access
// kind: endpoint
// name: demo-ssh
// source: structured
// sensitive: true
// owner: platform-team
// justification: Platform engineers operate the demo tenant hosts
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  (
    context.idc.groups has "22222222-2222-2222-2222-222222222222"
  ) &&
  (true) || (true) || (true) &&
  context.crowdstrike.assessment.overall >= 50
};
