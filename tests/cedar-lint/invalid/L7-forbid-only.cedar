// managed-by: terraform-aws-verified-access
// kind: group
// name: fixture
// source: structured
// owner: platform-team
// justification: Fixture: a policy with only a forbid
// user-context: idc
// device-context: crowdstrike
forbid(principal, action, resource)
when {
  context.http_request.http_method != "GET"
};
