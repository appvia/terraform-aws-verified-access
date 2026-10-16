// managed-by: terraform-aws-verified-access
// kind: endpoint
// name: demo-ssh
// source: structured
// sensitive: true
// owner: security-team
// justification: Only the on-call group may reach the production database hosts
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  (
    context.idc.groups has "d242c5b0-6081-1845-6fa8-6e0d9513c107"
  ) &&
  (context.idc.user.email.address like "*@example.com" || context.idc.user.email.address like "*@example.org") &&
  context.crowdstrike.assessment.overall >= 50
};
