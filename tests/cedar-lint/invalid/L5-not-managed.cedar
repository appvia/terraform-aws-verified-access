// kind: group
// name: fixture
// source: structured
// owner: platform-team
// justification: Fixture: a hand written policy
// user-context: idc
// device-context: crowdstrike
permit(principal, action, resource)
when {
  context.idc.groups has "11111111-1111-1111-1111-111111111111"
};
