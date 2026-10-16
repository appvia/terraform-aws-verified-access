# 0004: Access logs go to CloudWatch and the log archive, in OCSF 1.0.0-rc.2 with trust context

- **Status:** Accepted (2026-10-14); CloudWatch implemented, log archive designed
- **Deciders:** platform team

## Context

Verified Access logs every attempt to CloudWatch Logs, S3 or Firehose, in OCSF `0.1` or `1.0.0-rc.2`, optionally with trust context (identity and device data, which is personal data). It publishes no metrics, so monitoring depends on the logs.

## Decision

- **CloudWatch Logs**, 90 days, for queries, metric filters and alarms; **S3 in the log archive account**, 1 year with Object Lock, for the long term record.
- **OCSF `1.0.0-rc.2`:** required for trust context, and `0.1` cannot be used with TCP endpoints.
- **Trust context on:** a denial is only explainable with the user's groups.

## Consequences

- Personal data in logs: retention is bounded and read access restricted.
- The log archive copy needs a bucket and policy in the log archive account (not built in the spike).
- See [logging](../security.md#logging) and [operations](../operations.md#monitoring).
