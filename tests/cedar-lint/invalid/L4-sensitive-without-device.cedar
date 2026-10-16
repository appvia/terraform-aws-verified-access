// managed-by: terraform-aws-verified-access
// kind: endpoint
// name: fixture
// source: structured
// sensitive: true
// owner: platform-team
// justification: Fixture: a sensitive endpoint without device posture
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  context.idc.user.email.verified == true
};
