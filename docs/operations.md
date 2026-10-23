# Operations

Running Verified Access deployed with this module through a deployment repository (from `appvia/terraform-aws-pipeline-template`): what can be monitored, the alarms and dashboard, the runbook procedures, troubleshooting, certificate validation and teardown. For a first deployment, follow [getting started](getting-started.md).

## Monitoring

### What Verified Access publishes

**No CloudWatch metrics.** Verified Access is not in AWS's [list of services that publish CloudWatch metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/aws-services-cloudwatch-metrics.html); its [monitoring documentation](https://docs.aws.amazon.com/verified-access/latest/ug/monitoring-overview.html) lists only **access logs** and **CloudTrail**. Every metric is therefore derived from the access logs, or comes from a neighbouring service (the central NLB, CloudWatch Logs itself, CloudTrail, AWS Health).

### The four questions

| Question | Signal | Where |
| --- | --- | --- |
| **Is it up?** | NLB healthy targets per application; allowed access count; access log delivery (`IncomingLogEvents`) | NLB metrics, log derived metric, CloudWatch Logs metric |
| **What is failing?** | Unhealthy targets; HTTP 504s (applications slower than the 60 second idle timeout) and 5xx; denial spikes | NLB metrics, log derived metrics |
| **Who is connecting now?** | Allowed requests by user and endpoint, last seen | Saved Logs Insights query `<name_prefix>/<name>/who-is-connecting` |
| **What was denied?** | Denied requests with the user, target and reason | Saved Logs Insights query `<name_prefix>/<name>/denied-requests`, `AccessDenied` metric |

### Log derived metrics

Namespace `VerifiedAccess/<name_prefix>-<name>` (output `metric_namespace`; the resource name, so two deployments with the same `name` and different `name_prefix` in one account keep their metrics apart), created when CloudWatch logging is enabled (`access_logs.cloudwatch`). All four are created by default; `access_logs.cloudwatch.metric_filters` chooses which (`null` all, `[]` none). The saved queries are separate (`access_logs.cloudwatch.create_queries`, default on). HTTP and TCP events have different shapes, so each metric has a filter per shape.

| Metric key | Metric | HTTP filter | TCP filter |
| --- | --- | --- | --- |
| `access-allowed` | `AccessAllowed` | `$.actor.authorizations[0].decision = "Allow"` | `$.data.authorizations[0].decision = "Allow"` |
| `access-denied` | `AccessDenied` | `$.actor.authorizations[0].decision != "Allow"` | `$.data.authorizations[0].decision != "Allow"` |
| `http-504` | `Http504` | `$.http_response.code = 504` | n/a |
| `http-5xx` | `Http5xx` | `$.http_response.code >= 500` | n/a |

Confirmed with real traffic: a denied TCP connection logs `"decision": "Deny"`, `"status": "Failure"`, `"status_code": "403"`; 30 denied attempts produced `AccessDenied = 30`, and allowed sessions were counted in `AccessAllowed`.

Plan time checks keep the choices consistent: an alarm (built in or custom) on a log derived metric needs that metric's filter, the dashboard needs all four, and the default metric stream needs at least one. Choosing fewer filters, for example to keep only what Dash0 shows:

```hcl
  access_logs = {
    cloudwatch = {
      metric_filters = ["access-allowed", "access-denied"] # no HTTP endpoints, so no HTTP error metrics
    }
  }

  alarms = {
    rules = {
      http-504 = { enabled = false } # its metric is not created
    }
  }
```

### Metrics available

Output `metrics` lists every metric the module makes available in a deployment, keyed as below, each with its `namespace`, `metric_name`, `dimensions`, recommended `statistic`, `source` and `description`. Use the keys in `alarms.custom` and `metric_stream.include`. Endpoint metrics exist per load-balancer endpoint with `targets` (`topology = "hub"`), keyed `<endpoint>/<metric>`.

| Key | Namespace | Metric | Dimensions | Source | What it tells you | Statistic |
| --- | --- | --- | --- | --- | --- | --- |
| `access-allowed` | `VerifiedAccess/<name_prefix>-<name>` | `AccessAllowed` | none | log metric filter | Requests and connections allowed; zero for a day means nobody can get in | Sum |
| `access-denied` | `VerifiedAccess/<name_prefix>-<name>` | `AccessDenied` | none | log metric filter | Requests and connections denied; a spike is a bad policy change or probing | Sum |
| `http-504` | `VerifiedAccess/<name_prefix>-<name>` | `Http504` | none | log metric filter | Applications slower than the 60 second Verified Access limit | Sum |
| `http-5xx` | `VerifiedAccess/<name_prefix>-<name>` | `Http5xx` | none | log metric filter | Server errors from the applications or Verified Access | Sum |
| `incoming-log-events` | `AWS/Logs` | `IncomingLogEvents` | `LogGroupName` | AWS/Logs | Access log events arriving; none means logging stopped or no usage | Sum |
| `incoming-bytes` | `AWS/Logs` | `IncomingBytes` | `LogGroupName` | AWS/Logs | Access log volume, which drives the ingestion cost | Sum |
| `load-balancer-active-flow-count` | `AWS/NetworkELB` | `ActiveFlowCount` | `LoadBalancer` | AWS/NetworkELB | Concurrent connections through the central NLB | Maximum |
| `load-balancer-new-flow-count` | `AWS/NetworkELB` | `NewFlowCount` | `LoadBalancer` | AWS/NetworkELB | New connections through the central NLB | Sum |
| `load-balancer-processed-bytes` | `AWS/NetworkELB` | `ProcessedBytes` | `LoadBalancer` | AWS/NetworkELB | Traffic through the central NLB, both directions | Sum |
| `load-balancer-tcp-client-reset-count` | `AWS/NetworkELB` | `TCP_Client_Reset_Count` | `LoadBalancer` | AWS/NetworkELB | Resets sent by the client side (Verified Access) | Sum |
| `load-balancer-tcp-target-reset-count` | `AWS/NetworkELB` | `TCP_Target_Reset_Count` | `LoadBalancer` | AWS/NetworkELB | Resets sent by targets: a service refusing or dropping connections | Sum |
| `load-balancer-tcp-elb-reset-count` | `AWS/NetworkELB` | `TCP_ELB_Reset_Count` | `LoadBalancer` | AWS/NetworkELB | Resets generated by the NLB, for example idle timeouts | Sum |
| `load-balancer-port-allocation-error-count` | `AWS/NetworkELB` | `PortAllocationErrorCount` | `LoadBalancer` | AWS/NetworkELB | Dropped connections: address translation ran out of ports for a target | Sum |
| `<endpoint>/healthy-host-count` | `AWS/NetworkELB` | `HealthyHostCount` | `LoadBalancer`, `TargetGroup` | AWS/NetworkELB | Healthy targets for the endpoint; below 1 it is unreachable | Minimum |
| `<endpoint>/unhealthy-host-count` | `AWS/NetworkELB` | `UnHealthyHostCount` | `LoadBalancer`, `TargetGroup` | AWS/NetworkELB | Unhealthy targets for the endpoint; above 0 it is degraded | Maximum |

The log derived metrics appear only when their filter is created, the `AWS/Logs` metrics with `access_logs.cloudwatch`, and the `AWS/NetworkELB` metrics with `topology = "hub"`. The NLB metric names, dimensions and statistics are from the [NLB CloudWatch metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html) documentation; the NLB reports `ProcessedBytes`, the reset counts and the flow counts (`ActiveFlowCount`, `NewFlowCount`) per load balancer only, not per target group (confirmed on a live deployment), and reports nothing while no traffic flows. Connections per application are therefore not available as a metric; the access logs record every connection with its endpoint.

### Alarms

Module option `alarms`, with starting thresholds. Every customer needs the same alarm set; who is paged, which alarms and their thresholds differ, and those are inputs. Set `alarms` and the module creates the alarms below, all notifying one SNS topic: `<name_prefix>-<name>-alarms` with a topic policy allowing CloudWatch and EventBridge in this account, or your own topic (`create_sns_topic = false` with `sns_topic_arn`). The created topic can be encrypted with a key the module creates (`alarms.create_kms_key = true`) or an existing key (`alarms.kms_key_arn`, whose key policy must allow both services); set at most one of them. `alarms.email_addresses` subscribes recipients, who must confirm their SNS subscription before they receive anything. The log derived alarms need `access_logs.cloudwatch` with their metric filter (the default creates them all).

| # | Key | Default | Severity | What it means | What to do |
| --- | --- | --- | --- | --- | --- |
| A1 | `no-healthy-targets` (per endpoint with `targets`) | `HealthyHostCount` (Minimum) < 1, period 60, 2 evaluation periods, missing data breaching | Critical | The application is unreachable through the central NLB | Check the target is running and listening, its security group allows the hub subnets, and the transit gateway route ([troubleshooting](#troubleshooting)) |
| A2 | `unhealthy-targets` (per endpoint with `targets`) | `UnHealthyHostCount` (Maximum) > 0, period 60, 5 evaluation periods | Warning | Some targets fail their health check: the service is degraded | Find the failing target in the target group; check its health check port and path |
| A3 | `http-504` | `Http504` (Sum) >= 5, period 300, 1 evaluation period | Warning | Applications slower than the 60 second Verified Access idle timeout | Ask the tenant to speed up or stream the slow requests; Verified Access cannot wait longer |
| A4 | `access-denied` | `AccessDenied` (Sum) >= 20, period 300, 1 evaluation period | Warning | A bad policy change, or probing (proven in testing) | Run the `denied-requests` query: one user after a policy change means a policy fix; many sources means probing |
| A5 | `logging-stopped` | `IncomingLogEvents` (Sum) < 1, period 3600, 1 evaluation period, missing data breaching | Warning | Audit trail broken, or no usage (check A6) | Check the instance logging configuration and the log group; in a quiet environment, turn it off or lengthen it |
| A6 | `no-access-allowed` | `AccessAllowed` (Sum) < 1, period 3600, 24 evaluation periods, missing data breaching | Info | Nobody was allowed in for a day: a possible outage nobody reported | Try to connect; check the identity provider and the recent policy changes |
| A7 | `changed-outside-pipeline` (only with `pipeline_role_name`) | EventBridge: any non read-only `*VerifiedAccess*` API call by a principal other than the pipeline role, or by an IAM user or the root user, **anywhere in the account and region** (see below) | Critical (security) | Someone bypassed the [approval gate](security.md#the-approval-gate) | Find the caller in CloudTrail; revert the change through the pipeline |
| A8 | AWS Health event for Verified Access | EventBridge `aws.health` | Warning | | **Not built:** the Health event codes for Verified Access are not documented; add once confirmed |

Tune after real usage: A5 and A6 fire in quiet environments (no traffic means no logs), which is expected in a demo.

**A7 is account wide.** The rule cannot be scoped to this deployment's instance: the CloudTrail events of the Verified Access APIs do not carry the instance id consistently (a group policy change names only the group, an endpoint change only the endpoint, a trust provider change only the trust provider), so an event pattern on the instance id would miss most changes. The rule therefore matches every Verified Access change in the account and region. With several deployments of the module in one account, each one's rule alerts on changes to all of them, and a deployment whose pipeline role differs alerts on the other deployments' own pipeline. Use one pipeline role per account for all of them, and turn the rule on in one deployment only (`alarms.rules = { changed-outside-pipeline = { enabled = false } }` in the others).

### Customising the alarms

`alarms.rules` turns any alarm off or changes its settings, keyed by the alarm key above. A rule keyed by `no-healthy-targets` or `unhealthy-targets` applies to every endpoint; key one endpoint as `<endpoint>/no-healthy-targets` to override it alone (it wins over the rule for every endpoint). Unset settings keep the defaults, so `alarms = { email_addresses = [...] }` creates exactly the table above. The keys are checked at plan time.

| Setting | What it does | Example |
| --- | --- | --- |
| `alarms.rules.<key>.enabled` | `false` does not create the alarm (for `changed-outside-pipeline`, the EventBridge rule; this is the only setting it takes) | `no-access-allowed = { enabled = false }` in a quiet environment |
| `alarms.rules.<key>.threshold`, `period`, `evaluation_periods`, `treat_missing_data` | Change the alarm; period in seconds (10, 30 or a multiple of 60), period times evaluation periods at most seven days | `http-504 = { threshold = 3, period = 60, evaluation_periods = 5 }` |
| `alarms.custom.<name>` | Adds an alarm `<name_prefix>-<name>-<name>` on any key of the `metrics` output, notifying the same actions | see below |
| `alarms.additional_action_arns` | Also notifies these ARNs on alarm and on recovery, for example an SNS topic integrated with PagerDuty or AWS Chatbot | `["arn:aws:sns:eu-west-2:111111111111:pagerduty"]` |

Turn one alarm off, change a threshold, and override one endpoint:

```hcl
  alarms = {
    email_addresses        = ["platform-team@example.com"]
    additional_action_arns = ["arn:aws:sns:eu-west-2:111111111111:pagerduty"]
    rules = {
      no-access-allowed                = { enabled = false }                                    # a quiet environment
      http-504                         = { threshold = 3, period = 60, evaluation_periods = 5 } # 3 or more a minute, for 5 minutes
      no-healthy-targets               = { evaluation_periods = 5 }                             # ride out target restarts
      "tenant-a-ssh/unhealthy-targets" = { enabled = false }                                    # a single host: A1 covers it
    }
  }
```

Add a custom alarm on any metric the module makes available:

```hcl
  alarms = {
    email_addresses = ["platform-team@example.com"]
    custom = {
      denied-burst = {
        metric              = "access-denied"
        comparison_operator = "GreaterThanThreshold"
        threshold           = 100
        period              = 60
        description         = "More than 100 denied requests in a minute"
      }
      many-sessions = {
        metric              = "load-balancer-active-flow-count"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        threshold           = 50
        statistic           = "Maximum"
        evaluation_periods  = 3
      }
    }
  }
```

A custom alarm defaults to the `Sum` statistic, a 300 second period, 1 evaluation period and missing data treated as missing; its name must not clash with a module alarm. A metric that does not exist in the deployment (for example an endpoint metric without `topology = "hub"`) fails the plan with the list of available keys.

### Dashboard

Module option `dashboard`. `dashboard = {}` creates the CloudWatch dashboard `<name_prefix>-<name>` (output `dashboard_name`; requires `access_logs.cloudwatch` with all four metric filters, the default): access decisions (`AccessAllowed`, `AccessDenied`), HTTP errors (`Http504`, `Http5xx`), healthy targets per endpoint on the central NLB (`topology = "hub"`) and a Logs Insights table of who is connecting. `dashboard.period` sets the metric period (default 300 seconds; 60, 300, 900, 3600, 21600 or 86400).

### Metric stream, Dash0 or any external observability platform

| Signal | Route |
| --- | --- |
| Log derived and NLB metrics | **Module option `metric_stream`**: a CloudWatch metric stream (`<name_prefix>-<name>`, OpenTelemetry 1.0 by default; `json` and `opentelemetry0.7` also accepted) to a Firehose delivery stream you provide (`firehose_arn`, with the `role_arn` CloudWatch assumes to write to it, or `create_role = true`), for example one delivering to Dash0. By default it streams `VerifiedAccess/<name_prefix>-<name>` and, with `topology = "hub"`, `AWS/NetworkELB`; `metric_stream.include` streams only the chosen keys of the `metrics` output |
| Raw access logs | `access_logs.firehose` to a Firehose stream (`delivery_stream_name` of yours, or `create = true` for one writing to S3), or a CloudWatch Logs subscription filter (outside the module), to Dash0 (or Dash0's own AWS integration if already in place) |
| Stays in AWS only | The S3 archive (retention, immutability), the security alarm A7 (owned by security), Logs Insights queries |

Stream only some metrics to Dash0:

```hcl
  metric_stream = {
    firehose_arn = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/dash0"
    create_role  = true
    include      = ["access-allowed", "access-denied", "tenant-a-ssh/healthy-host-count"]
  }
```

The stream groups the keys by namespace and filters by metric name. A metric stream cannot filter by dimension, so an `AWS/NetworkELB` or `AWS/Logs` metric is streamed for every load balancer or log group in the account and region, not just this deployment's (`tenant-a-ssh/healthy-host-count` streams `HealthyHostCount` of every target group). The Firehose delivery stream and its destination are platform specific, so they stay outside the module.

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
3. HTTPS only: make sure the certificate covers the application domain (the module `certificate` covers one level below its `domain_name`), then add a CNAME from the application domain to the endpoint domain (output `application_domains`), unless the module publishes it with `dns`.
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

With `dns` (a Route 53 public hosted zone), the module publishes them, and with `wait_for_validation` waits for them; nothing to do by hand. Otherwise, with the module `certificate`, read the `certificate_validation_records` output after the first apply and create each record (name => value, type CNAME) in the domain's DNS. The certificate is issued a few minutes later. With `certificate.wait_for_validation = true` the apply waits for issue before creating the endpoints that use it, so publish the records first (or apply once without waiting).

### Changes that recreate resources

Most changes are made in place, but some arguments cannot be changed on an existing AWS resource, so Terraform replaces the resource, and a replaced resource replaces whatever must point at it. Read the plan for `must be replaced` before merging. Replacing an **endpoint** gives it a new endpoint domain: application CNAMEs must be repointed (the module does it with `dns`), TCP users connect to the new name (output `endpoint_domains`), and the new endpoint takes about 17 minutes to become active, during which the application is unreachable. Replacing the **instance** or the **user trust provider** also means re-exporting the Connectivity Client configuration ([connect over TCP](#connect-over-tcp-ssh-rdp-databases)). Checked against the `ForceNew` arguments of AWS provider v6.68.0 (`internal/service/ec2/verifiedaccess_*.go`, `internal/service/elbv2`); rows marked *unverified* follow from the provider schema but have not been applied against AWS.

| Change | Replaced | Not replaced (updated in place) |
| --- | --- | --- |
| `name_prefix` or `name` | The central NLB (its name), and with it every listener and every endpoint with `targets`; every target group (name hash; created before destroyed); every module endpoint security group (name and description), and so every endpoint using one; the load balancer security group; renamed logging and monitoring resources (log group, metric filters, queries, alarms, dashboard, topic, keys' aliases, metric stream, web ACL) | The instance, trust providers and groups (only their `Name` tags change) |
| `load_balancer.private_ips`, or removing a subnet from `subnet_ids` with `topology = "hub"` | The central NLB, every listener and every endpoint with `targets` | Target groups and their targets; adding a subnet updates the NLB in place |
| An endpoint's `create_security_group`, or `security_group_ids` | The endpoint (its security groups cannot change) | |
| `load_balancer.create_security_group`, `load_balancer.security_group_ids` | The load balancer security group is created or destroyed | The NLB (its security groups change in place, as it always keeps at least one) |
| An endpoint's `endpoint_domain_prefix`, `application_domain`, `domain_certificate_arn` (or the module `certificate`, which is replaced when its `domain_name` changes), `type`, `cidr`, `load_balancer_arn`, `network_interface_id`, `rds` ARNs, or `subnet_ids` of a cidr or rds endpoint | The endpoint | |
| An endpoint's `port`, `port_ranges` or `protocol` | With `targets`: its target group (a new name, created before the old one is destroyed) and the target registrations. The listener moves to the new target group once the targets are registered in it; the old registrations are removed first, so expect a short interruption until the targets pass their first health checks | The endpoint and its listener; the security group rules |
| An endpoint's `targets` or `target_details` | The registrations of the changed targets | The target group, listener and endpoint |
| Moving an endpoint to another group (same endpoint name) | | The endpoint (its group changes in place) |
| Renaming an endpoint or a group (its map key) | The renamed endpoint, or the group and every endpoint in it, unless a `moved` block maps the old key to the new one | |
| `vpc_id` | Every security group and target group, and so every endpoint | |
| `fips_enabled` | The instance and the trust provider attachments; the groups are moved to the new instance in place. Plan it as a migration: AWS may refuse to delete the old instance while groups are attached | Groups, endpoints |
| `user_trust_provider.type` or `policy_reference_name`, or the OIDC `issuer`, endpoints, `client_id` or `public_signing_key_endpoint` | The user trust provider and its attachment (a new `policy_reference_name` also re-renders every policy) | The instance, groups and endpoints; the OIDC client secrets change in place |
| `device_trust_provider.type` or `tenant_id` | The device trust provider and its attachment | |
| `kms_key_arn`, `create_kms_key`, `description`, policies, tags | | Everything (in place) |

### Tear down

1. Deployment repository: run the destroy workflow. If the pipeline role is not allowed to delete ACM certificates, first set `certificate = null` and add a `removed` block for `module.<name>.aws_acm_certificate.current` (`lifecycle { destroy = false }`), so the certificate leaves state without being deleted (the endpoints using it need their own `domain_certificate_arn`, or are destroyed in the same change); an unused public certificate is free and expires. With `load_balancer.enable_deletion_protection = true`, turn it off and apply before destroying.
2. Remove the tenant side: security group rules for the endpoint subnets and the application DNS records.
3. Resources the module created on request need care before destroying:
   - **Access log bucket** (`access_logs.s3.create`): the destroy fails while the bucket holds log objects, unless `force_destroy = true` (set it and apply first). With `object_lock`, locked object versions cannot be deleted by anyone until their retention ends (in `COMPLIANCE` mode not even by the root user), so the bucket cannot be destroyed until then; remove it from state with a `removed` block (`lifecycle { destroy = false }`) and let the lifecycle rule empty it. Object Lock cannot be turned off, and turning `object_lock` on or off later replaces the bucket.
   - **KMS keys** (`create_kms_key`, `access_logs.cloudwatch.create_kms_key`, `alarms.create_kms_key`): a destroy schedules key deletion after a 30 day window, during which `aws kms cancel-key-deletion` restores it. Once deleted, anything still encrypted with it is unreadable: Verified Access configuration encrypted with the key, and log events in the log group.
   - **Existing instance** (`existing_instance`): the destroy removes only the groups, endpoints and central NLB; the instance and its trust providers stay with their owner.

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
| Alarms "logging stopped" (A5) and "no successful access" (A6) firing | No traffic in a quiet environment | Expected; turn them off or lengthen them in `alarms.rules` ([customising the alarms](#customising-the-alarms)) |
| No alarm emails arrive | The SNS subscription was not confirmed | Each recipient confirms the email from AWS |
