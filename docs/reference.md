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
| `access_logs.cloudwatch` | object | optional | CloudWatch Logs destination; by default the module creates the log group so retention is always bounded |
| `access_logs.cloudwatch.log_group_name` | `string` | `null` | The log group name, defaults to /aws/verified-access/<name>; required when create_log_group is false |
| `access_logs.cloudwatch.create_log_group` | `bool` | `true` | Create the log group; false delivers to an existing log group (log_group_name), whose retention and encryption are then owned elsewhere, and retention_in_days and kms_key_arn are ignored |
| `access_logs.cloudwatch.retention_in_days` | `number` | `90` | The number of days to retain the logs |
| `access_logs.cloudwatch.kms_key_arn` | `string` | `null` | An optional customer managed KMS key used to encrypt the log group |
| `access_logs.cloudwatch.enable_metric_filters` | `bool` | `true` | Create log derived metric filters and saved Logs Insights queries |
| `access_logs.s3` | object | optional | S3 destination; the bucket is owned elsewhere (e.g. log archive) and carries its own retention and object lock |
| `access_logs.s3.bucket_name` | `string` | required | The name of the bucket |
| `access_logs.s3.bucket_owner` | `string` | `null` | The account id that owns the bucket, required when the bucket is in another account |
| `access_logs.s3.prefix` | `string` | `null` | An optional prefix for the log objects |
| `access_logs.firehose_delivery_stream_name` | `string` | `null` | Kinesis Data Firehose delivery stream name, e.g. for a third party SIEM |

### `alarms`

Alarms on the log derived metrics, the central load balancer and changes made outside the pipeline; null disables alarms. Requires CloudWatch access logs with metric filters.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `alarms.sns_topic_arn` | `string` | `null` | An existing SNS topic to notify, defaults to a topic created by the module (verified-access-<name>-alarms) |
| `alarms.create_kms_key` | `bool` | `false` | Encrypt the created topic with a customer managed KMS key the module creates (verified-access-<name>-alarms) |
| `alarms.kms_key_arn` | `string` | `null` | Encrypt the created topic with an existing customer managed KMS key; its key policy must permit CloudWatch and EventBridge. Leave both unset for an unencrypted topic |
| `alarms.email_addresses` | `list(string)` | `[]` | The email addresses subscribed to the topic; each recipient must confirm the subscription |
| `alarms.pipeline_role_name` | `string` | `null` | The role the deployment pipeline assumes; when set, any other principal changing Verified Access raises an alarm |
| `alarms.thresholds` | object | optional | The alarm thresholds; starting values, to be tuned from real usage |
| `alarms.thresholds.http_504` | `number` | `5` | The number of HTTP 504 responses in five minutes |
| `alarms.thresholds.access_denied` | `number` | `20` | The number of denied requests in five minutes |
| `alarms.thresholds.logging_stopped_hours` | `number` | `1` | The number of hours without access log events before alarming |
| `alarms.thresholds.no_access_allowed_hours` | `number` | `24` | The number of hours without an allowed request before alarming |
| `alarms.disabled` | `list(string)` | `[]` | The alarms not to create, by key: http-504, access-denied, logging-stopped, no-access-allowed, no-healthy-targets and unhealthy-targets (the last two are per endpoint with targets) |
| `alarms.additional_action_arns` | `list(string)` | `[]` | Additional ARNs notified on alarm and on recovery, e.g. an SNS topic subscribed by PagerDuty or AWS Chatbot |
| `alarms.overrides` | map of objects | optional | Per alarm overrides of the period (seconds), evaluation periods and threshold, keyed like disabled; overrides win over thresholds |
| `alarms.overrides.<key>.period` | `number` | `null` | The period in seconds: 10, 30 or a multiple of 60 |
| `alarms.overrides.<key>.evaluation_periods` | `number` | `null` | The number of periods evaluated |
| `alarms.overrides.<key>.threshold` | `number` | `null` | The threshold compared with the statistic |

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

### `dashboard`

An optional CloudWatch dashboard (verified-access-<name>) showing access decisions, HTTP errors, load balancer health and who is connecting; null disables it. Requires CloudWatch access logs with metric filters.

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
| `groups.<key>.endpoints.<key>.security_group_ids` | `list(string)` | `[]` | Additional security groups to attach to the endpoint |
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

An optional customer managed KMS key used to encrypt Verified Access trust providers, groups and endpoints.

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

### `metric_stream`

An optional CloudWatch metric stream of the log derived metrics (and, with topology hub, the AWS/NetworkELB namespace) to a Kinesis Data Firehose delivery stream, e.g. for an external observability platform; null disables it.

Default: `null`

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `metric_stream.firehose_arn` | `string` | required | The ARN of the Kinesis Data Firehose delivery stream receiving the metrics |
| `metric_stream.role_arn` | `string` | required | The ARN of the IAM role CloudWatch assumes to write to the delivery stream |
| `metric_stream.output_format` | `string` | `"opentelemetry1.0"` | The output format (json, opentelemetry0.7, opentelemetry1.0) |

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

The user identity trust provider, IAM Identity Center or an OIDC identity provider.

Required.

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
| `alarm_kms_key_arn` | The ARN of the KMS key encrypting the alarm topic, when encrypted |
| `alarm_topic_arn` | The ARN of the SNS topic notified by the alarms, when enabled |
| `application_domains` | A map of application domain to the endpoint domain it must be a CNAME of, for http and https endpoints i.e. tools.example.com => tools-web.edge-xxx.vai-xxx.prod.verified-access.eu-west-2.amazonaws.com; published by the module with dns |
| `certificate_arn` | The ARN of the wildcard certificate requested by the module, when enabled |
| `certificate_validation_records` | A map of DNS record name to value (CNAME) proving ownership of the certificate domain; publish them in the domain's DNS |
| `client_configuration_command` | The AWS CLI command exporting the Connectivity Client configuration of the instance; needs ec2:ExportVerifiedAccessInstanceClientConfiguration |
| `dashboard_name` | The name of the CloudWatch dashboard, when enabled |
| `device_trust_provider_id` | The id of the device trust provider, when configured |
| `endpoint_device_validation_domains` | A map of endpoint name to the domain Verified Access uses to validate devices for it |
| `endpoint_domains` | A map of endpoint name to the DNS name generated by Verified Access i.e. demo-ssh => edge-xxx.vai-xxx.prod.verified-access.eu-west-2.amazonaws.com |
| `endpoint_ids` | A map of endpoint name to Verified Access endpoint id |
| `endpoint_security_group_ids` | A map of endpoint name to the security group attached to its network interfaces; targets must allow traffic from the endpoint subnets |
| `group_arns` | A map of group name to Verified Access group ARN, e.g. for IAM policies or sharing |
| `group_ids` | A map of group name to Verified Access group id |
| `instance_arn` | The ARN of the Verified Access instance |
| `instance_id` | The id of the Verified Access instance |
| `load_balancer_arn` | The ARN of the central load balancer, when topology is hub |
| `load_balancer_dns_name` | The DNS name of the central load balancer, when topology is hub |
| `load_balancer_security_group_id` | The id of the central load balancer security group, when topology is hub |
| `metric_namespace` | The CloudWatch namespace of the log derived metrics (AccessAllowed, AccessDenied, Http504, Http5xx), when enabled |
| `name_servers` | The name servers of the instance, used to delegate cidr_endpoints_custom_subdomain |
| `oidc_redirect_uris` | A map of http and https endpoint name to the sign-in redirect URI to register with the OIDC client (https://<application_domain>/oauth2/idpresponse), when the user trust provider is oidc |
| `rendered_policies` | A map of the rendered Cedar policies i.e. group/<name> and endpoint/<name> => policy; used for review, lint and golden tests |
| `target_group_arns` | A map of endpoint name to the ARN of its target group on the central load balancer, for endpoints with targets |
| `user_trust_provider_id` | The id of the user trust provider |
| `web_acl_arn` | The ARN of the web ACL associated with the instance, when enabled |
