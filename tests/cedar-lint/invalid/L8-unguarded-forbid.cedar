// managed-by: terraform-aws-verified-access
// kind: group
// name: fixture
// source: raw
// owner: security-team
// justification: Fixture: a forbid on an HTTP field without a guard, skipped on TCP endpoints
// user-context: idc
permit(principal, action, resource)
when {
  context.idc.groups has "11111111-1111-1111-1111-111111111111"
};
forbid(principal, action, resource)
when {
  context.http_request.http_method != "GET"
};
