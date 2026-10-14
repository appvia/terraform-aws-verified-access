// managed-by: terraform-aws-verified-access
// kind: endpoint
// name: demo-ssh
// source: structured
// sensitive: true
// owner: platform-team
// justification: Platform engineers operate the demo tenant hosts
// user-context: idc
// device-context: jumpcloud
permit(principal, action, resource)
when {
  context.jumpcloud.device.is_managed == true
};
