# Security

How access is approved, how policies are checked before they reach AWS, how identity is used, and what is logged. Diagrams of the network and traffic paths are in [how it works](how-it-works.md).

## The approval gate

Access follows a two stage model: a tenant provisions its service, and only the platform team wires up access to it. A tenant cannot expose its own service ([ADR 0001](adr/0001-endpoints-in-network-account.md)).

### Where the gate sits and who holds it

```mermaid
flowchart LR
  R[Service desk request] --> PR[Pull request<br/>deployment repository]
  PR --> G1{Access Policy Gate<br/>no AWS credentials}
  G1 -->|rendered Cedar matches policies/<br/>and passes lint| G2{Terraform plan<br/>read-only role}
  G2 --> REV{Review<br/>code owners}
  REV -->|approved, merged to main| AP[Terraform apply<br/>read-write role, main only]
  AP --> AWS[(Verified Access)]
  AWS -.->|any change by another principal| ALERT[Alert: changed outside the pipeline]
```

| Control | Where | Held by |
| --- | --- | --- |
| Only the platform team can create endpoints | Endpoints live in the network account; tenants have no access there, and groups are not shared to tenant accounts | Platform team |
| Every change is a pull request | Deployment repository; the pipeline role can only apply from `main` | Platform team |
| Review is mandatory | `CODEOWNERS` plus branch protection on `main` (require code owner review, require the gate and plan checks, no bypass) | Code owners (the platform team) |
| The effective policy is reviewed, not just the intent | `policies/*.cedar` must match what the module renders, or the gate fails | Reviewer |
| Unsafe policies cannot be merged | Cedar lint rules L1 to L8 (parse, no unscoped permit, owner and justification, device context on sensitive endpoints, no forbid that is silently skipped) | The pipeline |
| Changes outside the pipeline are detected | EventBridge rule on Verified Access write APIs by any principal other than the pipeline role, to the alarm topic (module `alarms.pipeline_role_name`, alarm [A7](operations.md#alarms)) | Platform team (alert recipients) |

> **Branch protection must be enabled** on the deployment repository's `main`. Without it, anyone with write access can push to `main` and the pipeline applies the change unreviewed.

### Requesting access

1. The tenant raises a service desk request: the service, its private address and port, and who needs access.
2. A platform engineer opens a pull request in the deployment repository: the endpoint with its `targets` and the group, with the rendered Cedar in `policies/`.
3. The policy gate and plan run; the platform team reviews and merges; the pipeline applies.
4. The service desk ticket links the pull request, which is the audit trail.

The exact changes are in [everyday tasks](getting-started.md#everyday-tasks).

### Audit trail for one approval

1. **Request:** the service desk ticket (who asked, why).
2. **Pull request:** the author, the reviewers and approvals, the tfvars change (intent) and the `policies/*.cedar` diff (effect), with the plan as a comment.
3. **Pipeline run:** the gate result, the plan and the apply log, linked from the merge commit.
4. **CloudTrail:** `ModifyVerifiedAccessGroupPolicy` (and similar) by the pipeline role, with the time it took effect.
5. **Access logs:** every allowed and denied attempt afterwards, with the user and their groups.

### A worked example

Revoking a group's access and granting another: the author changes `identity_groups` in the deployment repository's tfvars. The gate **fails** until the reviewed copy in `policies/` is updated, so the pull request shows the exact effect:

```diff
 permit(principal, action, resource)
 when {
   (
-    context.idc.groups has "11111111-1111-1111-1111-111111111111"
+    context.idc.groups has "22222222-2222-2222-2222-222222222222"
   )
 };
```

After review and merge the pipeline applies it; in testing, changes took effect within about 10 minutes, and a user outside the new group was denied.

### The escape hatch (raw Cedar)

When the structured input cannot express a rule:

1. Write `policies/raw/<name>.cedar` in the deployment repository and reference it as `raw_policy = { cedar = file(...), owner = "...", justification = "..." }` (on a group, or on an endpoint for an endpoint policy).
2. Lint still runs (a raw policy cannot contain an unscoped permit), and rule L6 lists every raw policy in the job summary.
3. `CODEOWNERS` on `/policies/raw/` requires the security reviewers' approval.
4. The pull request template asks why the structured interface was not enough; repeated needs become structured features.

### Optional organisation guardrail

A service control policy denying `ec2:CreateVerifiedAccessEndpoint` and `ec2:ModifyVerifiedAccess*` outside the network account (or for principals other than the pipeline role) makes the gate impossible to bypass even for account administrators.

## How policies are rendered and checked

Policies are declared as structured input (`groups[*].policy`: `identity_groups`, `owner`, `justification`) and rendered to [Cedar](https://www.cedarpolicy.com/) by the module, with deterministic output and a machine readable header. New to Cedar? [Access policies](policies.md) explains it, with worked examples. Reviewers read the input and the `rendered_policies` output, not hand written Cedar ([ADR 0005](adr/0005-policies-reviewed-as-rendered-cedar.md)). Each access change touches two files, the intent and the effect: intended friction.

| Layer | What it does | Where |
| --- | --- | --- |
| **Plan time validation** | Rejects malformed or over-broad input, for example an empty `identity_groups` (an unscoped permit, which would let anyone who can sign in through), Identity Center group names instead of ids, a missing owner or a justification under 10 characters, or an endpoint marked `sensitive` without a `device_trust_provider` | `variables.tf`, at `terraform plan` |
| **Sensitive endpoints** | Receive an endpoint policy requiring device posture; group and endpoint policies must both allow | Module, `sensitive = true` on an endpoint |
| **Endpoint policies** | Narrow one endpoint within its group, rendered and linted like group policies ([endpoint policies](#endpoint-policies)) | Module, `policy` on an endpoint |
| **Lint** | `scripts/cedar-lint.sh` checks rendered and raw policies against the rule set documented in the script (L1 to L8: parse with the official Cedar CLI, no unscoped permit, owner and justification, device context on sensitive endpoints, raw policies listed, protocol specific forbids guarded); `scripts/test-cedar-lint.sh` proves each rule | The Access Policy Gate in the deployment pipeline |
| **Golden files** | `tests/policy.tftest.hcl` asserts the rendered Cedar for each scenario against `tests/golden/*.cedar`, so a change in policy semantics is visible in the diff | This repository |
| **Reviewed copy** | The deployment repository keeps a copy of every rendered policy in `policies/`; a test fails if they differ, so every access change shows its Cedar diff in the pull request | Deployment repository |
| **Escape hatch** | `raw_policy` accepts hand written Cedar where the structured input cannot express a rule; keep raw policies in a dedicated directory protected by `CODEOWNERS` so they always receive a security review | Deployment repository |

### Endpoint policies

A group policy decides who may reach any endpoint in the group. An endpoint can carry its own structured policy to narrow that further, for example to the on-call group only, or to staff with an `example.com` address:

```hcl
        prod-db = {
          # ... endpoint settings ...
          sensitive = true
          policy = {
            identity_groups       = ["22222222-2222-2222-2222-222222222222"]
            additional_conditions = ["context.idc.user.email.address like \"*@example.com\""]
            owner                 = "security-team"                                    # optional; defaults to the group's
            justification         = "Only the on-call engineers may reach production data" # set both or neither
          }
        }
```

It renders to one `permit` whose conditions are all combined with **AND**: any of the endpoint's `identity_groups`, then each additional condition (each wrapped in parentheses, so an `||` inside one cannot widen the rest), then the device posture condition when the endpoint is `sensitive`. Verified Access evaluates the group policy and the endpoint policy and allows a request only if **both** allow it, so an endpoint policy can only narrow access, never widen it: a user must be in one of the group's identity groups **and** one of the endpoint's.

```cedar
permit(principal, action, resource)
when {
  (
    context.idc.groups has "22222222-2222-2222-2222-222222222222"
  ) &&
  (context.idc.user.email.address like "*@example.com") &&
  context.crowdstrike.assessment.overall >= 50
};
```

Plan time checks: an endpoint sets at most one of `policy` and `raw_policy`; the policy must reference a trust provider (identity groups, `sensitive`, or a condition on the user or device context), as lint rule L2 requires; Identity Center groups are ids; and conditions are single expressions without semicolons or line breaks, so they cannot end the `permit` and start another statement. Anything the structured input cannot express still goes through `raw_policy`.

## Identity

- **Identity group membership is the access control** ([ADR 0003](adr/0003-identity-center-groups-as-the-control.md)): Identity Center group ids, or OIDC group names, sorted, in the rendered Cedar. Access is managed where identities already are, so joiners and leavers flow through the identity provider. Groups are created per audience, not per tenant.
- **The verified email condition is off by default** (`user_trust_provider.require_verified_email = false`). IAM Identity Center can report `email.verified = false` for every user (for example when users are provisioned from an external directory), and requiring it then denies everyone, including members of the permitted group. Turn it on only where the directory verifies emails; customers who rely on verified emails must opt in.
- **No device posture by default:** anyone in the group can connect from any device with the client. Customers with Jamf, CrowdStrike or JumpCloud can add a `device_trust_provider` (`crowdstrike_min_score`, default 50, or `jamf_allowed_risk`, default `LOW` and `SECURE`, for sensitive endpoints); device context for TCP endpoints must be tested first (risk R1).
- **OIDC:** the client secret is passed in `oidc_client_secret`; source it from a secret store, never from tfvars. Add `offline_access` to the scopes for the Connectivity Client. It is stored in Terraform state like any argument, so encrypt and restrict the state.
- **OIDC groups claim:** policies match group names in the `groups` claim of the user context (`context.<policy_reference_name>.groups`). Providers that put groups elsewhere are supported with `user_trust_provider.oidc.groups_claim`, for example `additional_user_context.groups` renders `context.okta.additional_user_context.groups.contains("admins")`. Check a log event with trust context (or the provider's user info response) for where the groups actually are before changing it: a wrong claim denies everyone. Claims that are not plain names (for example URL namespaced claims) need `raw_policy`.
- **OIDC native application client:** the Connectivity Client uses the browser client (`client_id`, `scope`, `oidc_client_secret`) unless `native_client_id`, `native_scope` and `oidc_native_client_secret` configure a separate native application client, as some identity providers require. The `oidc_redirect_uris` output lists the sign-in redirect URI to register for each web application.
- **Encryption:** `kms_key_arn` encrypts the trust providers, groups and endpoints with a customer managed key.

The supported providers are listed in [trust providers](how-it-works.md#trust-providers).

## Logging

Verified Access logs every access attempt, allowed or denied, in Open Cybersecurity Schema Framework (OCSF) format, to CloudWatch Logs, S3 or Firehose ([ADR 0004](adr/0004-logging-destinations-and-format.md)).

### Decisions

| # | Decision | Module default | Recommended deployment | Why |
| --- | --- | --- | --- | --- |
| LG1 | **Trust context** (identity and device data) in the logs | `include_trust_context = false` (data protection by default) | **On** | Investigation needs the identity: a denial is only explainable with the user's groups (see the example below). It is personal data, so retention is bounded |
| LG2 | **Destinations** | CloudWatch, S3 and Firehose all supported, any combination | CloudWatch **and** S3 in the log archive account | CloudWatch for live queries, metrics and alarms; S3 for long term, tamper resistant records |
| LG3 | **OCSF version** | `ocsf-1.0.0-rc.2` (AWS's own default is `ocsf-0.1`) | `ocsf-1.0.0-rc.2` | Not a preference: trust context **requires** rc.2, and `ocsf-0.1` cannot be used with TCP endpoints. The module rejects incompatible combinations at plan time |
| LG4 | **Retention** | The module creates the log group with 90 days | CloudWatch 90 days; production S3 1 year (lifecycle rule) | Bounded retention for personal data; long term copy where storage is cheap |
| LG5 | **Who can read, who cannot delete** | n/a (the bucket is owned elsewhere) | Production: read limited to security and operations roles; S3 Object Lock (compliance mode) for the retention period | Object Lock makes the record tamper proof; it is irreversible, so it is not used for demo data |
| LG6 | **Encryption** | Optional `kms_key_arn` for the log group | A customer managed key on the log group and SSE-KMS on the bucket | Logs hold personal data; the pipeline role needs permission to use the keys |

The module warns at plan time when no access logging is configured. The S3 bucket in the log archive account, with its policy, is owned outside the module.

**Consistency with VPC flow logs:** treat access logs like flow logs, as network security records: same log archive account, same retention class, same read restrictions and immutability. Where an estate has no established flow log pattern to mirror, these decisions set it.

### What a log event tells you

A denied SSH attempt (trimmed). `include_trust_context = true` is what makes the `context` block, and therefore the reason, visible:

```json
{
  "class_name": "Authorization",
  "data": {
    "endpoint_type": "load-balancer",
    "protocol": "tcp",
    "authorizations": [{ "decision": "Deny", "policy": { "name": "inline" } }],
    "context": {
      "tcp_flow": { "client_ip": "203.0.113.10", "destination_ip": "10.10.2.98", "destination_port": 22 },
      "idc": {
        "user": { "user_name": "jane@example.com", "email": { "address": "jane@example.com", "verified": false } },
        "groups": { "11111111-1111-1111-1111-111111111111": { "group_name": "Engineers" } }
      }
    }
  },
  "status": "Failure",
  "status_code": "403",
  "privileges": ["vae-0123456789abcdef0"],
  "user": { "email_addr": "jane@example.com" }
}
```

Here the user is in a permitted group but `email.verified` is `false`: with `require_verified_email = true` this is the reason for the denial, which is why the condition is off by default.

### Where to find logs

| Need | Where |
| --- | --- |
| Live investigation | CloudWatch Logs Insights, saved queries `verified-access/<name>/denied-requests` and `who-is-connecting` |
| Long term record | S3 in the log archive account |
| Who changed access | CloudTrail `ModifyVerifiedAccess*` events and the deployment repository's pull requests |
