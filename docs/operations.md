# Operations

Running Verified Access deployed with this module through a deployment repository (from `appvia/terraform-aws-pipeline-template`): what can be monitored, the alarms and dashboard, the runbook procedures, troubleshooting, certificate validation and teardown. For a first deployment, follow [getting started](getting-started.md).

## Monitoring

### What Verified Access publishes

**No CloudWatch metrics.** Verified Access is not in AWS's list of services that publish CloudWatch metrics; its monitoring documentation lists only **access logs** and **CloudTrail**. Every metric is therefore derived from the access logs, or comes from a neighbouring service (the central NLB, CloudWatch Logs itself, CloudTrail, AWS Health).

### The four questions

| Question | Signal | Where |
| --- | --- | --- |
| **Is it up?** | NLB healthy targets per application; allowed access count; access log delivery (`IncomingLogEvents`) | NLB metrics, log derived metric, CloudWatch Logs metric |
| **What is failing?** | Unhealthy targets; HTTP 504s (applications slower than the 60 second idle timeout) and 5xx; denial spikes | NLB metrics, log derived metrics |
| **Who is connecting now?** | Allowed requests by user and endpoint, last seen | Saved Logs Insights query `verified-access/<name>/who-is-connecting` |
| **What was denied?** | Denied requests with the user, target and reason | Saved Logs Insights query `verified-access/<name>/denied-requests`, `AccessDenied` metric |

### Log derived metrics

Namespace `VerifiedAccess/<name>` (output `metric_namespace`), created when CloudWatch logging is enabled (`access_logs.cloudwatch.enable_metric_filters`, default on), together with the saved queries. HTTP and TCP events have different shapes, so each metric has a filter per shape.

| Metric | HTTP filter | TCP filter |
| --- | --- | --- |
| `AccessAllowed` | `$.actor.authorizations[0].decision = "Allow"` | `$.data.authorizations[0].decision = "Allow"` |
| `AccessDenied` | `$.actor.authorizations[0].decision != "Allow"` | `$.data.authorizations[0].decision != "Allow"` |
| `Http504` | `$.http_response.code = 504` | n/a |
| `Http5xx` | `$.http_response.code >= 500` | n/a |

Confirmed with real traffic: a denied TCP connection logs `"decision": "Deny"`, `"status": "Failure"`, `"status_code": "403"`; 30 denied attempts produced `AccessDenied = 30`, and allowed sessions were counted in `AccessAllowed`.

With `topology = "hub"`, the central NLB also publishes the standard `AWS/NetworkELB` metrics (`HealthyHostCount`, `UnHealthyHostCount` per target group), and CloudWatch Logs publishes `IncomingLogEvents` for the log group.

### Alarms

Module option `alarms`, with starting thresholds. Every customer needs the same alarm set; only who is paged and the thresholds differ, and those are inputs. Set `alarms` (requires `access_logs.cloudwatch` with metric filters) and the module creates A1 to A7, all to one SNS topic: `verified-access-<name>-alarms` with a topic policy allowing CloudWatch and EventBridge in this account, or your own topic with `alarms.sns_topic_arn`. The created topic can be encrypted with a key the module creates (`alarms.create_kms_key = true`) or an existing key (`alarms.kms_key_arn`, whose key policy must allow both services); set at most one of them. `alarms.email_addresses` subscribes recipients, who must confirm their SNS subscription before they receive anything. A1 and A2 are created per endpoint with `targets` when `topology = "hub"`; A7 is created when `alarms.pipeline_role_name` is set.

| # | Alarm | Threshold | Severity | Why |
| --- | --- | --- | --- | --- |
| A1 | NLB **no healthy targets** (per application) | `HealthyHostCount` < 1 for 2 x 1 minute, missing data breaching | Critical | Application unreachable |
| A2 | NLB **unhealthy targets** (per application) | `UnHealthyHostCount` > 0 for 5 x 1 minute | Warning | Tenant service degraded |
| A3 | **HTTP 504s** | `Http504` >= 5 in 5 minutes (`thresholds.http_504`) | Warning | Applications slower than the 60 second Verified Access idle timeout |
| A4 | **Denial spike** | `AccessDenied` >= 20 in 5 minutes (`thresholds.access_denied`) | Warning | A bad policy change, or probing (proven in testing) |
| A5 | **Logging stopped** | `IncomingLogEvents` < 1 for 1 hour (`thresholds.logging_stopped_hours`), missing data breaching | Warning | Audit trail broken, or no usage (check A6) |
| A6 | **No successful access** | `AccessAllowed` < 1 for 24 hours (`thresholds.no_access_allowed_hours`), missing data breaching | Info | A possible outage nobody reported |
| A7 | **Changed outside the pipeline** | EventBridge: any non read-only `*VerifiedAccess*` API call by a principal other than the pipeline role (`pipeline_role_name`), or by an IAM user or the root user | Critical (security) | Protects the [approval gate](security.md#the-approval-gate) |
| A8 | **AWS Health** event for Verified Access | EventBridge `aws.health` | Warning | **Not built:** the Health event codes for Verified Access are not documented; add once confirmed |

Thresholds must be at least 1, and the hour thresholds at most 168 (seven days). Tune after real usage: A5 and A6 fire in quiet environments (no traffic means no logs), which is expected in a demo.

### Dashboard

Module option `dashboard`. `dashboard = {}` creates the CloudWatch dashboard `verified-access-<name>` (output `dashboard_name`; requires `access_logs.cloudwatch` with metric filters): access decisions (`AccessAllowed`, `AccessDenied`), HTTP errors (`Http504`, `Http5xx`), healthy targets per endpoint on the central NLB (`topology = "hub"`) and a Logs Insights table of who is connecting. `dashboard.period` sets the metric period (default 300 seconds; 60, 300, 900, 3600, 21600 or 86400).

### Metric stream, Dash0 or any external observability platform

| Signal | Route |
| --- | --- |
| Log derived and NLB metrics | **Module option `metric_stream`**: a CloudWatch metric stream (`verified-access-<name>`, OpenTelemetry 1.0 by default; `json` and `opentelemetry0.7` also accepted) of `VerifiedAccess/<name>` and, with `topology = "hub"`, `AWS/NetworkELB`, to a Firehose delivery stream you provide (`firehose_arn`, with the `role_arn` CloudWatch assumes to write to it), for example one delivering to Dash0. Requires `access_logs.cloudwatch` with metric filters |
| Raw access logs | `access_logs.firehose_delivery_stream_name` straight to a Firehose stream, or a CloudWatch Logs subscription filter (outside the module), to Dash0 (or Dash0's own AWS integration if already in place) |
| Stays in AWS only | The S3 archive (retention, immutability), the security alarm A7 (owned by security), Logs Insights queries |

The Firehose delivery stream and its destination are platform specific, so they stay outside the module. Metric stream include filters match whole namespaces: `AWS/NetworkELB` carries every network load balancer in the account and region, not just the central one.

### Timings worth knowing

| Event | Observed |
| --- | --- |
| Access log events reach CloudWatch | About 3 to 5 minutes after the attempt |
| A policy change takes effect | About 5 to 10 minutes after the apply |
| A new endpoint becomes active | About 17 minutes |

## Runbook

Each procedure is a change to the deployment repository; the exact snippets are in [everyday tasks](getting-started.md#everyday-tasks).

### Give someone access to an application

1. Find the Identity Center group ID (or OIDC group name) for the audience ([where to find it](getting-started.md#identity-center-group-ids)).
2. In the deployment repository, change `groups` in `values/production.tfvars`.
3. Run `terraform test -var-file=values/production.tfvars`. It fails because the rendered policy changed: update the matching file in `policies/` with the new Cedar (the failure shows which), then run it again.
4. Open a pull request; check the plan; get a code owner review; merge.
5. **Allow about 10 minutes** after the apply before the change takes effect.

Revoking access is the same change in reverse, with the same delay.

### Add an application

1. The tenant allows the endpoint subnets on the application's port in its security group.
2. Add an endpoint under the right group (`type = "load-balancer"`; TCP with a single `port_ranges` entry, or HTTP with `port` and `application_domain`) with the application's private IPs in `targets` (`topology = "hub"`). Each application needs its own port on the central load balancer; the module creates the listener, target group and security group rules.
3. HTTPS only: make sure the certificate covers the application domain (the module `certificate` covers one level below its `domain_name`), then add a CNAME from the application domain to the endpoint domain (output `endpoint_domains`).
4. Merge. **A new endpoint takes about 17 minutes** to become active; the pipeline waits for it.

### Connect over TCP (SSH, RDP, databases)

1. Install the [AWS Verified Access Connectivity Client](https://docs.aws.amazon.com/verified-access/latest/ug/connectivity-client.html) (macOS or Windows; signed installer only). Disconnect other VPNs; keep IPv6 enabled.
2. Get the configuration file: `aws ec2 export-verified-access-instance-client-configuration --verified-access-instance-id <instance_id>` saved as `ClientConfig-<anything>.json`. It needs `ec2:ExportVerifiedAccessInstanceClientConfiguration`, which read-only and engineer roles often lack; a manual workflow using the pipeline role is a simple way to provide it. In production, distribute it through MDM.
3. Install it, owned by root (macOS):
   ```bash
   sudo mkdir -p "/Library/Application Support/Connectivity Client"
   sudo cp ClientConfig-*.json "/Library/Application Support/Connectivity Client/"
   sudo chown root "/Library/Application Support/Connectivity Client/"ClientConfig-*.json
   ```
4. Open the client and sign in.
5. Connect to the endpoint domain (output `endpoint_domains`), for example `ssh ec2-user@<endpoint>.<instance>.prod.verified-access.<region>.amazonaws.com`. `scp` and `sftp` work the same way.

### Publish the certificate validation records

With the module `certificate`, read the `certificate_validation_records` output after the first apply and create each record (name => value, type CNAME) in the domain's DNS. The certificate is issued a few minutes later. With `certificate.wait_for_validation = true` the apply waits for issue before creating the endpoints that use it, so publish the records first (or apply once without waiting).

### Tear down

1. Deployment repository: run the destroy workflow. If the pipeline role is not allowed to delete ACM certificates, first set `certificate = null` and add a `removed` block for `module.<name>.aws_acm_certificate.current` (`lifecycle { destroy = false }`), so the certificate leaves state without being deleted (the endpoints using it need their own `domain_certificate_arn`, or are destroyed in the same change); an unused public certificate is free and expires. With `load_balancer.enable_deletion_protection = true`, turn it off and apply before destroying.
2. Remove the tenant side: security group rules for the endpoint subnets and the application DNS records.

## Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| `Could not resolve hostname` for a TCP endpoint | The client is not connected; TCP endpoint names resolve to **IPv6 only** | The client shows Connected; `ifconfig` shows a tunnel interface with an IPv6 address |
| TCP connection **times out** | **Denied** by policy (a denial looks like a timeout to the client), or the target is down, or a firewall between the hub and the tenant drops it ([inspection checklist](how-it-works.md#with-an-inspection-vpc)) | `denied-requests` saved query (logs arrive 3 to 5 minutes later); NLB target health |
| Browser shows **403** | Denied by policy | `denied-requests` saved query: the user's groups are in the event |
| Everyone is denied with Identity Center | The directory reports `email.verified = false` and `require_verified_email = true` | `context.idc.user.email.verified` in a log event; set `require_verified_email = false` |
| A policy change "did not work" | Propagation | Wait 10 minutes; confirm the policy with `aws ec2 get-verified-access-group-policy` |
| SSH session drops when idle | Load balancer idle timeout (350 seconds) | `ssh -o ServerAliveInterval=60`; or raise `load_balancer.tcp_idle_timeout_seconds` |
| HTTP 504 | The application took longer than 60 seconds | `Http504` metric; the application |
| Pipeline: `AssumeRoleWithWebIdentity` denied | The role trusts a different OIDC subject; new repositories use the immutable form `org@<id>/repo@<id>` | The repository's `actions/oidc/customization/sub`; the role's `repository` value |
| Pipeline: `jq: parse error` before Terraform | Transient GitHub token error | Re-run the failed jobs |
| Pipeline: `Saved plan is stale` | Re-ran only the apply after an earlier failure | Start a fresh run (`workflow_dispatch` on `main`) |
| Alarms "logging stopped" (A5) and "no successful access" (A6) firing | No traffic in a quiet environment | Expected; tune `alarms.thresholds` |
| No alarm emails arrive | The SNS subscription was not confirmed | Each recipient confirms the email from AWS |
