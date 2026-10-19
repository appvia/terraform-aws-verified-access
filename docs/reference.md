# Reference

Every input, nested setting and output of the module. Generated from the comments in `variables.tf` and `outputs.tf` by `scripts/generate-reference.py`; do not edit by hand. For how to use them, start with [getting started](getting-started.md).

## Inputs

### `access_logs`

Access logging configuration for the Verified Access instance; null disables logging (a check warns). Set for every live environment.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `access_logs.log_version` | `string` | `"ocsf-1.0.0-rc.2"` | The OCSF log version (ocsf-0.1, ocsf-1.0.0-rc.2); rc.2 is required for trust context and TCP endpoints |
| `access_logs.include_trust_context` | `bool` | `false` | Include identity and device trust context in the logs; this is personal data, so it is opt-in |
| `access_logs.cloudwatch` | object | optional | CloudWatch Logs destination: a log group the module creates (the default, so retention is always bounded), or an existing one (create = false and log_group_name) |
| `access_logs.cloudwatch.create` | `bool` | `true` | Create the log group; false delivers to an existing log group (log_group_name), whose retention and encryption are then owned elsewhere, and retention_in_days and kms_key_arn are ignored |
| `access_logs.cloudwatch.log_group_name` | `string` | `null` | The name of the existing log group; with create, the name of the log group to create, defaulting to /aws/<name_prefix>/<name> |
| `access_logs.cloudwatch.retention_in_days` | `number` | `90` | The number of days to retain the logs |
| `access_logs.cloudwatch.kms_key_arn` | `string` | `null` | An optional customer managed KMS key used to encrypt the log group; its key policy must permit logs.<region>.amazonaws.com |
| `access_logs.cloudwatch.create_kms_key` | `bool` | `false` | Instead of kms_key_arn: create a customer managed KMS key (alias/<name_prefix>-<name>-access-logs, rotation on) encrypting the created log group, usable only by CloudWatch Logs for that log group |
| `access_logs.cloudwatch.metric_filters` | `list(string)` | `null` | The log derived metrics to create, by key of the metrics output: access-allowed, access-denied, http-504 and http-5xx; null creates them all, [] none. Alarms, the dashboard and the metric stream need the ones they use |
| `access_logs.cloudwatch.create_queries` | `bool` | `true` | Create the saved Logs Insights queries who-is-connecting and denied-requests |
| `access_logs.s3` | object | optional | S3 destination: an existing bucket (bucket_name, e.g. in the log archive account, carrying its own retention and object lock), or one the module creates in this account (create = true) |
| `access_logs.s3.create` | `bool` | `false` | Create the bucket, with versioning, encryption, a public access block, bucket owner enforced ownership, a TLS only policy permitting Verified Access log delivery, a lifecycle expiry and optional object lock |
| `access_logs.s3.bucket_name` | `string` | `null` | The name of the existing bucket; with create, the name of the bucket to create, defaulting to <name_prefix>-<name>-access-logs-<account id> |
| `access_logs.s3.bucket_owner` | `string` | `null` | The account id that owns an existing bucket, required when the bucket is in another account |
| `access_logs.s3.prefix` | `string` | `null` | An optional prefix for the log objects |
| `access_logs.s3.retention_days` | `number` | `365` | Created bucket only: the days after which log objects expire (and their old versions a day later) |
| `access_logs.s3.object_lock` | object | optional | Created bucket only: S3 Object Lock default retention, making each log object undeletable for days. Object Lock can only be enabled when the bucket is created and never turned off; in COMPLIANCE mode nobody, not even the root user, can delete a locked object or the bucket until the retention ends |
| `access_logs.s3.object_lock.mode` | `string` | `"COMPLIANCE"` | The retention mode, COMPLIANCE or GOVERNANCE (users with s3:BypassGovernanceRetention may delete) |
| `access_logs.s3.object_lock.days` | `number` | required | The days each object is locked for |
| `access_logs.s3.kms_key_arn` | `string` | `null` | Created bucket only: a customer managed KMS key (SSE-KMS) for the log objects, defaulting to SSE-S3; its key policy must permit delivery.logs.amazonaws.com |
| `access_logs.s3.force_destroy` | `bool` | `false` | Created bucket only: delete the bucket on destroy even when it holds log objects (locked objects still block it) |
| `access_logs.firehose` | object | optional | Kinesis Data Firehose destination, e.g. for a third party SIEM: an existing delivery stream (delivery_stream_name), or one the module creates in this account (create = true) writing to an S3 bucket |
| `access_logs.firehose.create` | `bool` | `false` | Create the delivery stream, with the IAM role it writes to destination_bucket_arn with |
| `access_logs.firehose.delivery_stream_name` | `string` | `null` | The name of the existing delivery stream; with create, the name of the stream to create, defaulting to <name_prefix>-<name>-access-logs |
| `access_logs.firehose.destination_bucket_arn` | `string` | `null` | Created stream only, and required with it: the ARN of the S3 bucket the delivery stream writes to; a bucket in another account must permit the delivery stream role (output access_log_firehose_role_arn) in its bucket policy |
| `access_logs.firehose.prefix` | `string` | `null` | Created stream only: an optional prefix for the delivered objects |
| `access_logs.firehose.buffering_interval` | `number` | `300` | Created stream only: the seconds the delivery stream buffers before writing (0-900) |
| `access_logs.firehose.buffering_size` | `number` | `5` | Created stream only: the MiB the delivery stream buffers before writing (1-128) |
| `access_logs.firehose.kms_key_arn` | `string` | `null` | Created stream only: an optional customer managed KMS key encrypting the delivered objects (SSE-KMS); the role may use it via S3 |

### `alarms`

Alarms on the log derived metrics, the central load balancer and changes made outside the pipeline; null disables alarms. Each alarm can be turned off or tuned in rules, and custom alarms added on any metric the module makes available (output metrics). The log derived alarms need CloudWatch access logs with their metric filters.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `alarms.create_sns_topic` | `bool` | `true` | Create the topic the alarms notify (<name_prefix>-<name>-alarms); false notifies the existing topic in sns_topic_arn instead |
| `alarms.sns_topic_arn` | `string` | `null` | The existing SNS topic to notify, with create_sns_topic = false |
| `alarms.create_kms_key` | `bool` | `false` | Encrypt the created topic with a customer managed KMS key the module creates (<name_prefix>-<name>-alarms) |
| `alarms.kms_key_arn` | `string` | `null` | Encrypt the created topic with an existing customer managed KMS key; its key policy must permit CloudWatch and EventBridge. Leave both unset for an unencrypted topic |
| `alarms.email_addresses` | `list(string)` | `[]` | The email addresses subscribed to the topic; each recipient must confirm the subscription |
| `alarms.pipeline_role_name` | `string` | `null` | The role the deployment pipeline assumes; when set, any other principal changing Verified Access raises an alarm (the changed-outside-pipeline rule) |
| `alarms.additional_action_arns` | `list(string)` | `[]` | Additional ARNs notified on alarm and on recovery, e.g. an SNS topic subscribed by PagerDuty or AWS Chatbot |
| `alarms.rules` | map of objects | optional | Per alarm settings, keyed by alarm: http-504, access-denied, logging-stopped, no-access-allowed, no-healthy-targets and unhealthy-targets (the last two apply to every endpoint with targets; key one endpoint as <endpoint>/no-healthy-targets to override it alone), and changed-outside-pipeline (enabled only). An alarm without a rule, or a setting left unset, keeps the module default (docs/operations.md, Alarms) |
| `alarms.rules.<key>.enabled` | `bool` | `null` | Create the alarm; false turns it off. Unset means on, or for an <endpoint>/<alarm> key the setting of <alarm> |
| `alarms.rules.<key>.threshold` | `number` | `null` | The threshold compared with the statistic |
| `alarms.rules.<key>.period` | `number` | `null` | The period in seconds: 10, 30 or a multiple of 60 |
| `alarms.rules.<key>.evaluation_periods` | `number` | `null` | The number of periods evaluated (period x evaluation_periods at most seven days) |
| `alarms.rules.<key>.treat_missing_data` | `string` | `null` | How missing data is treated: missing, ignore, breaching or notBreaching |
| `alarms.custom` | map of objects | optional | Additional alarms keyed by name (lowercase kebab-case, alarm <name_prefix>-<name>-<key>), on any metric the module makes available, notifying the same actions |
| `alarms.custom.<key>.metric` | `string` | required | The metric, by key of the metrics output, e.g. access-denied or <endpoint>/unhealthy-host-count |
| `alarms.custom.<key>.comparison_operator` | `string` | required | The comparison: GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold or LessThanOrEqualToThreshold |
| `alarms.custom.<key>.threshold` | `number` | required | The threshold compared with the statistic |
| `alarms.custom.<key>.statistic` | `string` | `"Sum"` | The statistic: Sum, Average, Minimum, Maximum or SampleCount; the metrics output recommends one per metric |
| `alarms.custom.<key>.period` | `number` | `300` | The period in seconds: 10, 30 or a multiple of 60 |
| `alarms.custom.<key>.evaluation_periods` | `number` | `1` | The number of periods evaluated (period x evaluation_periods at most seven days) |
| `alarms.custom.<key>.treat_missing_data` | `string` | `"missing"` | How missing data is treated: missing, ignore, breaching or notBreaching |
| `alarms.custom.<key>.description` | `string` | `null` | The alarm description, shown in the notification |

### `allowed_egress_cidr_blocks`

The CIDR blocks endpoint security groups may send traffic to when the target range cannot be derived (load-balancer, network-interface and rds endpoints).

Default: `["10.0.0.0/8"]`

### `certificate`

An optional wildcard public certificate (*.<domain_name>) for http and https endpoints that set no domain_certificate_arn; publish the certificate_validation_records output in the domain's DNS.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `certificate.domain_name` | `string` | required | The domain the certificate covers, e.g. example.com requests *.example.com |
| `certificate.wait_for_validation` | `bool` | `false` | Wait for the certificate to be issued before creating the endpoints that use it; publish the validation records first |

### `cidr_endpoints_custom_subdomain`

An optional custom subdomain for CIDR endpoints; delegate it to the name servers exported by the module.

Default: `null`

### `create_kms_key`

Instead of kms_key_arn: create a customer managed KMS key (alias/<name_prefix>-<name>, rotation on) encrypting the Verified Access trust providers, groups and endpoints, usable by Verified Access in this account. Deleting it makes their configuration unreadable, so it is deleted after a 30 day window.

Default: `false`

### `dashboard`

An optional CloudWatch dashboard (<name_prefix>-<name>) showing access decisions, HTTP errors, load balancer health and who is connecting; null disables it. Requires CloudWatch access logs with the metric filters access-allowed, access-denied, http-504 and http-5xx.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `dashboard.period` | `number` | `300` | The period in seconds of the metric widgets |

### `description`

The description of the Verified Access instance.

Default: `null`

### `dns`

An optional Route 53 public hosted zone where the module publishes the certificate validation records and the application CNAMEs (application_domain to endpoint domain) of http and https endpoints; null leaves DNS to the caller (outputs certificate_validation_records and application_domains).

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `dns.zone_id` | `string` | required | The id of the public hosted zone of the application domains, e.g. Z0123456789ABCDEFGHIJ |
| `dns.create_validation_records` | `bool` | `true` | Publish the validation records of the module certificate |
| `dns.create_application_records` | `bool` | `true` | Publish a CNAME from each http and https endpoint application_domain to its endpoint domain |
| `dns.ttl` | `number` | `300` | The TTL in seconds of the records |

### `device_trust_provider`

An optional device posture trust provider; null disables device posture.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `device_trust_provider.type` | `string` | required | The type of device trust provider (crowdstrike, jamf, jumpcloud) |
| `device_trust_provider.policy_reference_name` | `string` | `null` | The Cedar context key for the provider, defaults to the type, e.g. context.crowdstrike |
| `device_trust_provider.tenant_id` | `string` | required | The tenant id of the device provider application |
| `device_trust_provider.crowdstrike_min_score` | `number` | `50` | CrowdStrike only: the minimum assessment.overall score (1-100) for sensitive endpoints |
| `device_trust_provider.jamf_allowed_risk` | `list(string)` | `["LOW", "SECURE"]` | Jamf only: the risk levels permitted for sensitive endpoints |

### `existing_instance`

An existing Verified Access instance to add the groups and endpoints to, instead of creating one; null (the default) creates the instance. The instance, its trust providers, logging and web ACL are then owned elsewhere, so user_trust_provider, device_trust_provider, the OIDC client secrets, access_logs (and with it alarms, dashboard and metric_stream), waf, fips_enabled, description and cidr_endpoints_custom_subdomain must be left unset; the settings below describe the attached trust providers so the module can render the policies.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `existing_instance.id` | `string` | required | The id of the instance, e.g. vai-0123456789abcdef0 |
| `existing_instance.user_trust_provider_type` | `string` | `"iam-identity-center"` | The type of the user trust provider attached to the instance (iam-identity-center, oidc), which decides how identity groups are rendered |
| `existing_instance.user_policy_reference_name` | `string` | required | The Cedar context key (policy reference name) of the attached user trust provider, e.g. idc |
| `existing_instance.user_groups_claim` | `string` | `"groups"` | OIDC only: the claim holding the user's groups, as in user_trust_provider.oidc.groups_claim |
| `existing_instance.require_verified_email` | `bool` | `false` | IAM Identity Center only: require a verified email address in every group policy, as in user_trust_provider.require_verified_email |
| `existing_instance.device_trust_provider` | object | optional | The device trust provider attached to the instance, needed for sensitive endpoints; null when none is attached |
| `existing_instance.device_trust_provider.type` | `string` | required | The type of device trust provider (crowdstrike, jamf, jumpcloud) |
| `existing_instance.device_trust_provider.policy_reference_name` | `string` | `null` | The Cedar context key (policy reference name) of the attached provider, defaults to the type |
| `existing_instance.device_trust_provider.crowdstrike_min_score` | `number` | `50` | CrowdStrike only: the minimum assessment.overall score (1-100) for sensitive endpoints |
| `existing_instance.device_trust_provider.jamf_allowed_risk` | `list(string)` | `["LOW", "SECURE"]` | Jamf only: the risk levels permitted for sensitive endpoints |

### `fips_enabled`

Enable FIPS 140-2 validated endpoints on the Verified Access instance. Only supported in US, Canada and AWS GovCloud (US) regions (a check warns elsewhere); changing it replaces the instance and everything in it.

Default: `false`

### `groups`

The Verified Access groups keyed by name; each group holds its access policy and the endpoints it protects.

Default: `{}`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `groups.<key>.description` | `string` | `null` | The description of the group |
| `groups.<key>.policy` | object | optional | The structured access policy (preferred), rendered to Cedar by the module |
| `groups.<key>.policy.identity_groups` | `list(string)` | required | The identity groups permitted: Identity Center group ids, or OIDC group names |
| `groups.<key>.policy.owner` | `string` | required | The team accountable for this access |
| `groups.<key>.policy.justification` | `string` | required | Why this access exists |
| `groups.<key>.raw_policy` | object | optional | Escape hatch: a raw Cedar policy, e.g. file("policies/raw/<name>.cedar"); requires security review |
| `groups.<key>.raw_policy.cedar` | `string` | required | The Cedar policy text |
| `groups.<key>.raw_policy.owner` | `string` | required | The team accountable for this access |
| `groups.<key>.raw_policy.justification` | `string` | required | Why the structured policy cannot express this access |
| `groups.<key>.tags` | `map(string)` | `{}` | Tags merged over var.tags on the group and on every endpoint in it, e.g. a cost centre for chargeback |
| `groups.<key>.endpoints` | map of objects | optional | The endpoints in this group keyed by name; names must be unique across all groups |
| `groups.<key>.endpoints.<key>.type` | `string` | required | The endpoint type (load-balancer, network-interface, cidr, rds); cidr endpoints only reach addresses in the endpoint's own VPC, so reach services across a transit gateway with a load-balancer endpoint and an NLB with IP targets |
| `groups.<key>.endpoints.<key>.description` | `string` | `null` | The description of the endpoint |
| `groups.<key>.endpoints.<key>.protocol` | `string` | `"tcp"` | The protocol (http, https, tcp); cidr and rds endpoints are tcp only |
| `groups.<key>.endpoints.<key>.sensitive` | `bool` | `false` | Sensitive endpoints receive an endpoint policy requiring device posture |
| `groups.<key>.endpoints.<key>.port` | `number` | `null` | The port for http/https and rds endpoints |
| `groups.<key>.endpoints.<key>.port_ranges` | list of objects | optional | The port ranges for tcp endpoints |
| `groups.<key>.endpoints.<key>.port_ranges[*].from_port` | `number` | required | The first port of the range |
| `groups.<key>.endpoints.<key>.port_ranges[*].to_port` | `number` | required | The last port of the range (the same as from_port for a single port) |
| `groups.<key>.endpoints.<key>.load_balancer_arn` | `string` | `null` | The load balancer arn (load-balancer endpoints) |
| `groups.<key>.endpoints.<key>.targets` | `list(string)` | `[]` | The IPv4 addresses of the service across the transit gateway (load-balancer endpoints with topology hub); the module creates a listener and target group on the central load balancer instead of using load_balancer_arn |
| `groups.<key>.endpoints.<key>.target_details` | list of objects | optional | Instead of targets: the service addresses with an optional per target port (defaults to the endpoint port) and availability zone ("all" for addresses outside the load balancer VPC, or the zone name of an address inside it) |
| `groups.<key>.endpoints.<key>.target_details[*].ip` | `string` | required | The IPv4 address of the target |
| `groups.<key>.endpoints.<key>.target_details[*].port` | `number` | `null` | The port of the target, defaults to the endpoint port |
| `groups.<key>.endpoints.<key>.target_details[*].availability_zone` | `string` | `"all"` | The availability zone of the target; all for addresses across a transit gateway |
| `groups.<key>.endpoints.<key>.listener_port` | `number` | `null` | Hub only: the port of the listener on the central load balancer, which is also the port clients connect to on the endpoint domain; defaults to the endpoint port. Set it to put several services on the same port (e.g. SSH hosts on 22) behind the central load balancer: each keeps port_ranges (or port) as its service port |
| `groups.<key>.endpoints.<key>.health_check` | object | optional | Hub only: the target group health check; defaults to TCP on the traffic port |
| `groups.<key>.endpoints.<key>.health_check.protocol` | `string` | `"TCP"` | The health check protocol (TCP, HTTP or HTTPS) |
| `groups.<key>.endpoints.<key>.health_check.port` | `string` | `"traffic-port"` | The port checked, defaults to the port receiving traffic |
| `groups.<key>.endpoints.<key>.health_check.path` | `string` | `null` | The path checked (HTTP and HTTPS health checks only) |
| `groups.<key>.endpoints.<key>.health_check.healthy_threshold` | `number` | `3` | Consecutive successes before a target is healthy (2-10) |
| `groups.<key>.endpoints.<key>.health_check.unhealthy_threshold` | `number` | `3` | Consecutive failures before a target is unhealthy (2-10) |
| `groups.<key>.endpoints.<key>.health_check.interval` | `number` | `30` | The seconds between checks (5-300) |
| `groups.<key>.endpoints.<key>.deregistration_delay` | `number` | `null` | Hub only: the seconds the target group drains a deregistered target (0-3600), defaults to 300 |
| `groups.<key>.endpoints.<key>.preserve_client_ip` | `bool` | `null` | Hub only: preserve the client address at the target, defaults to false. Targets across a transit gateway reply to that address directly, bypassing the load balancer, so leave it off unless the return path is known |
| `groups.<key>.endpoints.<key>.proxy_protocol_v2` | `bool` | `null` | Hub only: send a proxy protocol v2 header to the targets, defaults to false; the targets must expect it |
| `groups.<key>.endpoints.<key>.network_interface_id` | `string` | `null` | The network interface id (network-interface endpoints) |
| `groups.<key>.endpoints.<key>.cidr` | `string` | `null` | The CIDR block (cidr endpoints) |
| `groups.<key>.endpoints.<key>.rds` | object | optional | The RDS target (rds endpoints); set exactly one of the arns |
| `groups.<key>.endpoints.<key>.rds.instance_arn` | `string` | `null` | The RDS instance ARN |
| `groups.<key>.endpoints.<key>.rds.cluster_arn` | `string` | `null` | The Aurora cluster ARN |
| `groups.<key>.endpoints.<key>.rds.proxy_arn` | `string` | `null` | The RDS Proxy ARN |
| `groups.<key>.endpoints.<key>.rds.endpoint` | `string` | required | The database endpoint address users connect to |
| `groups.<key>.endpoints.<key>.application_domain` | `string` | `null` | The public DNS name users browse to (http/https endpoints only) |
| `groups.<key>.endpoints.<key>.domain_certificate_arn` | `string` | `null` | The public ACM certificate for the application domain (http/https endpoints only) |
| `groups.<key>.endpoints.<key>.endpoint_domain_prefix` | `string` | `null` | The prefix for the generated endpoint domain, defaults to the endpoint name |
| `groups.<key>.endpoints.<key>.subnet_ids` | `list(string)` | `null` | Override the subnets for this endpoint, defaults to var.subnet_ids |
| `groups.<key>.endpoints.<key>.security_group_ids` | `list(string)` | `[]` | Additional security groups to attach to the endpoint; with create_security_group false, the only ones |
| `groups.<key>.endpoints.<key>.create_security_group` | `bool` | `true` | Create the endpoint security group (<name_prefix>-<name>-<endpoint>, egress only to the targets); false uses only security_group_ids, whose rules must then allow the endpoint to reach its targets |
| `groups.<key>.endpoints.<key>.egress_cidr_blocks` | `list(string)` | `null` | Override the CIDR blocks the endpoint security group may send to |
| `groups.<key>.endpoints.<key>.policy` | object | optional | A structured endpoint policy, evaluated in addition to the group policy (both must allow): identity groups narrowing the group's audience and additional Cedar conditions, all combined with AND (and with the device condition when sensitive). The owner and justification default to the group's |
| `groups.<key>.endpoints.<key>.policy.identity_groups` | `list(string)` | `[]` | The identity groups permitted to this endpoint (any of); empty leaves the group policy's audience |
| `groups.<key>.endpoints.<key>.policy.additional_conditions` | `list(string)` | `[]` | Extra Cedar conditions, each one line, all of which must hold |
| `groups.<key>.endpoints.<key>.policy.owner` | `string` | `null` | The team accountable for this access, defaults to the group policy owner |
| `groups.<key>.endpoints.<key>.policy.justification` | `string` | `null` | Why this access exists, defaults to the group policy justification |
| `groups.<key>.endpoints.<key>.raw_policy` | object | optional | Escape hatch: a raw Cedar endpoint policy; requires security review |
| `groups.<key>.endpoints.<key>.raw_policy.cedar` | `string` | required | The Cedar policy text |
| `groups.<key>.endpoints.<key>.raw_policy.owner` | `string` | required | The team accountable for this access |
| `groups.<key>.endpoints.<key>.raw_policy.justification` | `string` | required | Why the structured policy cannot express this access |
| `groups.<key>.endpoints.<key>.tags` | `map(string)` | `{}` | Tags merged over var.tags and the group tags on the endpoint, its security group, target group and listener |

### `kms_key_arn`

An optional customer managed KMS key used to encrypt Verified Access trust providers, groups and endpoints; its key policy must permit kms:CreateGrant, DescribeKey, GenerateDataKey and Decrypt via verified-access.<region>.amazonaws.com.

Default: `null`

### `load_balancer`

Settings for the central internal network load balancer created with topology hub, which reaches services across the transit gateway.

Default: `{}`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `load_balancer.private_ips` | `map(string)` | `{}` | Fixed private IPv4 addresses for the load balancer keyed by subnet id, so firewalls and tenants can allow exact addresses; changing them replaces the load balancer |
| `load_balancer.enable_deletion_protection` | `bool` | `false` | Protect the load balancer from deletion |
| `load_balancer.tcp_idle_timeout_seconds` | `number` | `350` | The idle timeout in seconds of the TCP listeners (60-6000); keep SSH sessions alive with ServerAliveInterval |
| `load_balancer.cross_zone_enabled` | `bool` | `true` | Balance across the targets in every availability zone; IP targets across a transit gateway have no zone of their own (availability zone all), so leave it on unless the targets are zonal |
| `load_balancer.max_security_group_rules` | `number` | `60` | The rules per security group quota of the account (default 60, inbound and outbound counted separately, one rule per address range); raise it here after raising the quota (Service Quotas, Amazon VPC) |
| `load_balancer.create_security_group` | `bool` | `true` | Create the load balancer security group (<name_prefix>-<name>-nlb, in from the module subnets on the listener ports, out to each target); false uses only security_group_ids, whose rules must then allow the endpoint subnets in on the listener ports and the targets out on their target and health check ports |
| `load_balancer.security_group_ids` | `list(string)` | `[]` | Security groups attached to the load balancer: in addition to the created one, or instead of it with create_security_group false |

### `metric_stream`

An optional CloudWatch metric stream to a Kinesis Data Firehose delivery stream, e.g. for an external observability platform: by default the log derived metrics and, with topology hub, the AWS/NetworkELB namespace, or only the metrics chosen in include; null disables it.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `metric_stream.firehose_arn` | `string` | required | The ARN of the Kinesis Data Firehose delivery stream receiving the metrics |
| `metric_stream.role_arn` | `string` | `null` | The ARN of an existing IAM role CloudWatch assumes to write to the delivery stream |
| `metric_stream.create_role` | `bool` | `false` | Instead of role_arn: create the role (<name_prefix>-<name>-metric-stream), trusted by CloudWatch metric streams in this account and permitted to write only to firehose_arn |
| `metric_stream.output_format` | `string` | `"opentelemetry1.0"` | The output format (json, opentelemetry0.7, opentelemetry1.0) |
| `metric_stream.include` | `list(string)` | `null` | The metrics to stream, by key of the metrics output, e.g. ["access-denied", "<endpoint>/healthy-host-count"]; null streams every log derived metric and, with topology hub, the whole AWS/NetworkELB namespace. A stream filters by namespace and metric name, not dimension, so an AWS/NetworkELB or AWS/Logs metric is streamed for every load balancer or log group in the account and region |

### `name`

The name of the Verified Access deployment, used to name and tag all resources, e.g. production.

Required.

### `name_prefix`

The prefix of all resource names, to follow the caller's naming convention, e.g. prod-euw2-va gives prod-euw2-va-<name>-nlb; scope pipeline roles to <name_prefix>-*.

Default: `"verified-access"`

### `oidc_client_secret`

The OAuth client secret for an OIDC user trust provider; source it from a secret store, never from tfvars.

Default: `null`

### `oidc_native_client_secret`

The OAuth client secret of a separate native application client (user_trust_provider.oidc.native_client_id), defaults to oidc_client_secret; source it from a secret store, never from tfvars.

Default: `null`

### `subnet_ids`

The dedicated subnets for the Verified Access endpoint network interfaces, one per availability zone.

Required.

### `tags`

The tags to apply to all resources.

Required.

### `topology`

The network topology: single-vpc (endpoints reach services in their own VPC) or hub (a central internal network load balancer reaches services in spoke VPCs across a transit gateway).

Default: `"single-vpc"`

### `user_trust_provider`

The user identity trust provider the module creates, IAM Identity Center or an OIDC identity provider; required unless existing_instance is set, which describes the provider already attached instead.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `user_trust_provider.type` | `string` | required | The type of user trust provider (iam-identity-center, oidc) |
| `user_trust_provider.policy_reference_name` | `string` | `"idc"` | The Cedar context key for the provider, used by both the trust provider and the rendered policies |
| `user_trust_provider.require_verified_email` | `bool` | `false` | Require a verified email address (IAM Identity Center only); off by default, as directories that do not verify emails (Identity Center reports email.verified = false) would deny every user |
| `user_trust_provider.oidc` | object | optional | The OIDC settings, required when type is oidc |
| `user_trust_provider.oidc.issuer` | `string` | required | The OIDC issuer identifier |
| `user_trust_provider.oidc.authorization_endpoint` | `string` | required | The OIDC authorization endpoint |
| `user_trust_provider.oidc.token_endpoint` | `string` | required | The OIDC token endpoint |
| `user_trust_provider.oidc.user_info_endpoint` | `string` | required | The OIDC user info endpoint |
| `user_trust_provider.oidc.client_id` | `string` | required | The OAuth client id; the secret is passed in oidc_client_secret |
| `user_trust_provider.oidc.scope` | `string` | `"openid email groups offline_access"` | The space delimited scopes; offline_access enables refresh tokens |
| `user_trust_provider.oidc.public_signing_key_endpoint` | `string` | `null` | The public signing key endpoint, enables native application (Connectivity Client) access |
| `user_trust_provider.oidc.groups_claim` | `string` | `"groups"` | The claim holding the user's groups, rendered into the policies as context.<policy_reference_name>.<claim>; a dotted path reaches a nested claim, e.g. additional_user_context.groups |
| `user_trust_provider.oidc.native_client_id` | `string` | `null` | A separate OAuth client for the native application (Connectivity Client), defaults to client_id; its secret is passed in oidc_native_client_secret |
| `user_trust_provider.oidc.native_scope` | `string` | `null` | The scopes of the native application client, defaults to scope |

### `vpc_id`

The VPC containing the dedicated Verified Access subnets, used for the endpoint security groups.

Required.

### `waf`

An optional AWS WAF web ACL for the instance, either an existing one or one created by the module with AWS managed rule groups; null disables it. WAF applies to http and https endpoints only, and with IAM Identity Center it inspects requests before sign-in.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `waf.web_acl_arn` | `string` | `null` | The ARN of an existing regional web ACL to associate |
| `waf.create` | `bool` | `false` | Create a regional web ACL (verified-access-<name>) with the AWS common, known bad inputs and IP reputation rule groups |

## Outputs

| Output | Description |
| --- | --- |
| `access_log_group_name` | The name of the CloudWatch log group receiving the access logs, when enabled |
| `access_log_bucket_arn` | The ARN of the S3 bucket created for the access logs, when access_logs.s3.create |
| `access_log_bucket_name` | The name of the S3 bucket receiving the access logs, created or existing, when enabled |
| `access_log_firehose_arn` | The ARN of the Firehose delivery stream created for the access logs, when access_logs.firehose.create |
| `access_log_firehose_role_arn` | The ARN of the IAM role the created Firehose delivery stream writes to its bucket with; a bucket in another account must permit it |
| `access_log_kms_key_arn` | The ARN of the KMS key created to encrypt the access log group, when access_logs.cloudwatch.create_kms_key |
| `alarm_kms_key_arn` | The ARN of the KMS key encrypting the alarm topic, when encrypted |
| `alarm_topic_arn` | The ARN of the SNS topic notified by the alarms, when enabled |
| `application_domains` | A map of application domain to the endpoint domain it must be a CNAME of, for http and https endpoints i.e. tools.example.com => tools-web.edge-xxx.vai-xxx.prod.verified-access.eu-west-2.amazonaws.com; published by the module with dns |
| `certificate_arn` | The ARN of the wildcard certificate requested by the module, when enabled |
| `certificate_validation_records` | A map of DNS record name to value (CNAME) proving ownership of the certificate domain; publish them in the domain's DNS |
| `client_configuration_command` | The AWS CLI command exporting the Connectivity Client configuration of the instance; needs ec2:ExportVerifiedAccessInstanceClientConfiguration |
| `dashboard_name` | The name of the CloudWatch dashboard, when enabled |
| `device_trust_provider_id` | The id of the device trust provider, when the module creates one |
| `endpoint_device_validation_domains` | A map of endpoint name to the domain Verified Access uses to validate devices for it |
| `endpoint_domains` | A map of endpoint name to the DNS name generated by Verified Access i.e. demo-ssh => edge-xxx.vai-xxx.prod.verified-access.eu-west-2.amazonaws.com |
| `endpoint_ids` | A map of endpoint name to Verified Access endpoint id |
| `endpoint_security_group_ids` | A map of endpoint name to the security group the module created for its network interfaces (null with create_security_group false); targets must allow traffic from the endpoint subnets |
| `group_arns` | A map of group name to Verified Access group ARN, e.g. for IAM policies or sharing |
| `group_ids` | A map of group name to Verified Access group id |
| `instance_arn` | The ARN of the Verified Access instance, created or existing |
| `instance_id` | The id of the Verified Access instance, created or existing |
| `load_balancer_arn` | The ARN of the central load balancer, when topology is hub |
| `load_balancer_dns_name` | The DNS name of the central load balancer, when topology is hub |
| `load_balancer_security_group_id` | The id of the central load balancer security group created by the module, when topology is hub (null with load_balancer.create_security_group false) |
| `kms_key_arn` | The ARN of the KMS key encrypting the trust providers, groups and endpoints, created (create_kms_key) or supplied, when set |
| `metric_namespace` | The CloudWatch namespace of the log derived metrics (AccessAllowed, AccessDenied, Http504, Http5xx), when any metric filter is created |
| `metric_stream_role_arn` | The ARN of the IAM role the metric stream writes to Firehose with, created (metric_stream.create_role) or supplied, when enabled |
| `metrics` | A map of every metric the module makes available, keyed as alarms.custom metric and metric_stream.include expect, to { namespace, metric_name, dimensions, statistic (recommended), source (log metric filter, AWS/Logs or AWS/NetworkELB), description } i.e. access-denied, incoming-log-events, load-balancer-processed-bytes and <endpoint>/healthy-host-count; Verified Access publishes no CloudWatch metrics of its own |
| `name_servers` | The name servers of the instance, used to delegate cidr_endpoints_custom_subdomain; empty with existing_instance |
| `oidc_redirect_uris` | A map of http and https endpoint name to the sign-in redirect URI to register with the OIDC client (https://<application_domain>/oauth2/idpresponse), when the user trust provider is oidc |
| `rendered_policies` | A map of the rendered Cedar policies i.e. group/<name> and endpoint/<name> => policy; used for review, lint and golden tests |
| `target_group_arns` | A map of endpoint name to the ARN of its target group on the central load balancer, for endpoints with targets |
| `user_trust_provider_id` | The id of the user trust provider, when the module creates the instance (null with existing_instance) |
| `web_acl_arn` | The ARN of the web ACL associated with the instance, when enabled |
