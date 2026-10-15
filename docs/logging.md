# Logging

Verified Access logs every access attempt, allowed or denied, in Open Cybersecurity Schema Framework (OCSF) format, to CloudWatch Logs, S3 or Firehose.

## Decisions

| # | Decision | Module default | Recommended deployment | Why |
| --- | --- | --- | --- | --- |
| LG1 | **Trust context** (identity and device data) in the logs | `include_trust_context = false` (data protection by default) | **On** | Investigation needs the identity: a denial is only explainable with the user's groups (see the example below). It is personal data, so retention is bounded |
| LG2 | **Destinations** | CloudWatch, S3 and Firehose all supported, any combination | CloudWatch **and** S3 in the log archive account | CloudWatch for live queries, metrics and alarms; S3 for long term, tamper resistant records |
| LG3 | **OCSF version** | `ocsf-1.0.0-rc.2` (AWS's own default is `ocsf-0.1`) | `ocsf-1.0.0-rc.2` | Not a preference: trust context **requires** rc.2, and `ocsf-0.1` cannot be used with TCP endpoints. The module rejects incompatible combinations at plan time |
| LG4 | **Retention** | The module creates the log group with 90 days | CloudWatch 90 days; production S3 1 year (lifecycle rule) | Bounded retention for personal data; long term copy where storage is cheap |
| LG5 | **Who can read, who cannot delete** | n/a (the bucket is owned elsewhere) | Production: read limited to security and operations roles; S3 Object Lock (compliance mode) for the retention period | Object Lock makes the record tamper proof; it is irreversible, so it is not used for demo data |
| LG6 | **Encryption** | Optional `kms_key_arn` for the log group | A customer managed key on the log group and SSE-KMS on the bucket | Logs hold personal data; the pipeline role needs permission to use the keys |

The module warns at plan time when no access logging is configured.

**Consistency with VPC flow logs:** treat access logs like flow logs, as network security records: same log archive account, same retention class, same read restrictions and immutability. Where an estate has no established flow log pattern to mirror, these decisions set it.

## What a log event tells you

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

## Where to find logs

| Need | Where |
| --- | --- |
| Live investigation | CloudWatch Logs Insights, saved queries `verified-access/<name>/denied-requests` and `who-is-connecting` |
| Long term record | S3 in the log archive account |
| Who changed access | CloudTrail `ModifyVerifiedAccess*` events and the deployment repository's pull requests |
