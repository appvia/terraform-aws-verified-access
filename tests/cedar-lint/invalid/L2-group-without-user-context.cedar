// managed-by: terraform-aws-verified-access
// kind: group
// name: fixture
// source: structured
// owner: platform-team
// justification: Fixture: a group permit without the user context
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  context.http_request.http_method == "GET"
};
