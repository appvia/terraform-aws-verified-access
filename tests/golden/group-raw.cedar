// managed-by: terraform-aws-verified-access
// kind: group
// name: auditors
// source: raw
// owner: security-team
// justification: Auditors are read-only: deny every non-GET request
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  context.idc.groups has "e242c5b0-6081-1845-6fa8-6e0d9513c107"
};
forbid(principal, action, resource)
unless {
  context has "http_request" && context.http_request.http_method == "GET"
};
