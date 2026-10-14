// managed-by: terraform-aws-verified-access
// kind: group
// name: fixture
// source: structured
// owner: 
// justification: Fixture: a policy without an owner
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  context.idc.groups has "c242c5b0-6081-1845-6fa8-6e0d9513c107"
};
