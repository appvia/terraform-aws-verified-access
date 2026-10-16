// managed-by: terraform-aws-verified-access
// kind: endpoint
// name: demo-break-glass
// source: raw
// sensitive: false
// owner: security-team
// justification: Break-glass access restricted to the incident response jump IP
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  context.idc.groups has "11111111-1111-1111-1111-111111111111" &&
  context.tcp_flow.client_ip == "192.0.2.10"
};
