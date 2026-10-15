# Observability

## What Verified Access publishes

**No CloudWatch metrics.** Verified Access is not in AWS's list of services that publish CloudWatch metrics; its monitoring documentation lists only **access logs** and **CloudTrail**. Every metric is therefore derived from the access logs, or comes from a neighbouring service (the central NLB, CloudWatch Logs itself, CloudTrail, AWS Health).

## The four questions

| Question | Signal | Where |
| --- | --- | --- |
| **Is it up?** | NLB healthy targets per application; allowed access count; access log delivery (`IncomingLogEvents`) | NLB metrics, log derived metric, CloudWatch Logs metric |
| **What is failing?** | Unhealthy targets; HTTP 504s (applications slower than the 60 second idle timeout) and 5xx; denial spikes | NLB metrics, log derived metrics |
| **Who is connecting now?** | Allowed requests by user and endpoint, last seen | Saved Logs Insights query `verified-access/<name>/who-is-connecting` |
| **What was denied?** | Denied requests with the user, target and reason | Saved Logs Insights query `verified-access/<name>/denied-requests`, `AccessDenied` metric |

## Log derived metrics (module)

Namespace `VerifiedAccess/<name>`, created when CloudWatch logging is enabled (`access_logs.cloudwatch.enable_metric_filters`, default on). HTTP and TCP events have different shapes, so each metric has a filter per shape.

| Metric | HTTP filter | TCP filter |
| --- | --- | --- |
| `AccessAllowed` | `$.actor.authorizations[0].decision = "Allow"` | `$.data.authorizations[0].decision = "Allow"` |
| `AccessDenied` | `$.actor.authorizations[0].decision != "Allow"` | `$.data.authorizations[0].decision != "Allow"` |
| `Http504` | `$.http_response.code = 504` | n/a |
| `Http5xx` | `$.http_response.code >= 500` | n/a |

Confirmed with real traffic: a denied TCP connection logs `"decision": "Deny"`, `"status": "Failure"`, `"status_code": "403"`; 30 denied attempts produced `AccessDenied = 30`, and allowed sessions were counted in `AccessAllowed`.

## Alarms (deployment repository, starting thresholds)

Alarms are customer specific (who is paged, thresholds, tooling), so they live in the deployment repository, not the module. A recommended starting set, all to one SNS topic:

| # | Alarm | Threshold | Severity | Why |
| --- | --- | --- | --- | --- |
| A1 | NLB **no healthy targets** (per application) | `HealthyHostCount` < 1 for 2 x 1 minute, missing data breaching | Critical | Application unreachable |
| A2 | NLB **unhealthy targets** (per application) | `UnHealthyHostCount` > 0 for 5 x 1 minute | Warning | Tenant service degraded |
| A3 | **HTTP 504s** | `Http504` >= 5 in 5 minutes | Warning | Applications slower than the 60 second Verified Access idle timeout |
| A4 | **Denial spike** | `AccessDenied` >= 20 in 5 minutes | Warning | A bad policy change, or probing (proven in testing) |
| A5 | **Logging stopped** | `IncomingLogEvents` < 1 for 60 minutes, missing data breaching | Warning | Audit trail broken, or no usage (check A6) |
| A6 | **No successful access** | `AccessAllowed` < 1 for 24 hours, missing data breaching | Info | A possible outage nobody reported |
| A7 | **Changed outside the pipeline** | EventBridge: any non read-only `*VerifiedAccess*` API call by a principal other than the pipeline role | Critical (security) | Protects the approval gate |
| A8 | **AWS Health** event for Verified Access | EventBridge `aws.health` | Warning | **Not built:** the Health event codes for Verified Access are not documented; add once confirmed |

Tune after real usage: A5 and A6 fire in quiet environments (no traffic means no logs), which is expected in a demo.

## Dash0 (or any external observability platform)

Designed, not built.

| Signal | Route |
| --- | --- |
| Log derived and NLB metrics | CloudWatch Metric Streams, Firehose, Dash0 |
| Raw access logs | CloudWatch Logs subscription filter, Firehose, Dash0 (or Dash0's own AWS integration if already in place) |
| Stays in AWS only | The S3 archive (retention, immutability), the security alarm A7 (owned by security), Logs Insights queries |

## Timings worth knowing

| Event | Observed |
| --- | --- |
| Access log events reach CloudWatch | About 3 to 5 minutes after the attempt |
| A policy change takes effect | About 5 to 10 minutes after the apply |
| A new endpoint becomes active | About 17 minutes |
