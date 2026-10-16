variable "access_logs" {
  description = "Access logging configuration for the Verified Access instance; null disables logging (a check warns). Set for every live environment"
  type = object({
    ## The OCSF log version (ocsf-0.1, ocsf-1.0.0-rc.2); rc.2 is required for trust context and TCP endpoints
    log_version = optional(string, "ocsf-1.0.0-rc.2")
    ## Include identity and device trust context in the logs; this is personal data, so it is opt-in
    include_trust_context = optional(bool, false)
    ## CloudWatch Logs destination; the module creates the log group so retention is always bounded
    cloudwatch = optional(object({
      # The log group name, defaults to /aws/verified-access/<name>
      log_group_name = optional(string, null)
      # The number of days to retain the logs
      retention_in_days = optional(number, 90)
      # An optional customer managed KMS key used to encrypt the log group
      kms_key_arn = optional(string, null)
      # Create log derived metric filters and saved Logs Insights queries
      enable_metric_filters = optional(bool, true)
    }), null)
    ## S3 destination; the bucket is owned elsewhere (e.g. log archive) and carries its own retention and object lock
    s3 = optional(object({
      # The name of the bucket
      bucket_name = string
      # The account id that owns the bucket, required when the bucket is in another account
      bucket_owner = optional(string, null)
      # An optional prefix for the log objects
      prefix = optional(string, null)
    }), null)
    ## Kinesis Data Firehose delivery stream name, e.g. for a third party SIEM
    firehose_delivery_stream_name = optional(string, null)
  })
  default = null

  # V17: at least one destination is configured
  validation {
    condition = var.access_logs == null ? true : (
      var.access_logs.cloudwatch != null || var.access_logs.s3 != null || var.access_logs.firehose_delivery_stream_name != null
    )
    error_message = "When access_logs is set, at least one of cloudwatch, s3 or firehose_delivery_stream_name must be configured."
  }

  # V18: the log version is supported by Verified Access
  validation {
    condition     = var.access_logs == null ? true : contains(["ocsf-0.1", "ocsf-1.0.0-rc.2"], var.access_logs.log_version)
    error_message = "The access_logs.log_version must be ocsf-0.1 or ocsf-1.0.0-rc.2."
  }

  # V19: trust context is only available on ocsf-1.0.0-rc.2
  validation {
    condition = var.access_logs == null ? true : (
      !var.access_logs.include_trust_context || var.access_logs.log_version == "ocsf-1.0.0-rc.2"
    )
    error_message = "Including trust context in the access logs requires log_version ocsf-1.0.0-rc.2."
  }

  # V20: TCP endpoints cannot be logged with ocsf-0.1
  validation {
    condition = var.access_logs == null ? true : (
      var.access_logs.log_version == "ocsf-1.0.0-rc.2" || !anytrue([
        for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.protocol == "tcp"
      ])
    )
    error_message = "TCP endpoints require access_logs.log_version ocsf-1.0.0-rc.2."
  }

  # V21: the retention period is a value CloudWatch Logs accepts
  validation {
    condition = var.access_logs == null ? true : (
      var.access_logs.cloudwatch == null ? true : contains(
        [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
        var.access_logs.cloudwatch.retention_in_days
      )
    )
    error_message = "The access_logs.cloudwatch.retention_in_days must be a value supported by CloudWatch Logs, e.g. 30, 90, 365."
  }
}

variable "alarms" {
  description = "Alarms on the log derived metrics, the central load balancer and changes made outside the pipeline; null disables alarms. Requires CloudWatch access logs with metric filters"
  type = object({
    ## An existing SNS topic to notify, defaults to a topic created by the module (verified-access-<name>-alarms)
    sns_topic_arn = optional(string, null)
    ## Encrypt the created topic with a customer managed KMS key the module creates (verified-access-<name>-alarms)
    create_kms_key = optional(bool, false)
    ## Encrypt the created topic with an existing customer managed KMS key; its key policy must permit CloudWatch and
    ## EventBridge. Leave both unset for an unencrypted topic
    kms_key_arn = optional(string, null)
    ## The email addresses subscribed to the topic; each recipient must confirm the subscription
    email_addresses = optional(list(string), [])
    ## The role the deployment pipeline assumes; when set, any other principal changing Verified Access raises an alarm
    pipeline_role_name = optional(string, null)
    ## The alarm thresholds; starting values, to be tuned from real usage
    thresholds = optional(object({
      # The number of HTTP 504 responses in five minutes
      http_504 = optional(number, 5)
      # The number of denied requests in five minutes
      access_denied = optional(number, 20)
      # The number of hours without access log events before alarming
      logging_stopped_hours = optional(number, 1)
      # The number of hours without an allowed request before alarming
      no_access_allowed_hours = optional(number, 24)
    }), {})
  })
  default = null

  # V35: the log derived alarms need the log derived metrics
  validation {
    condition     = var.alarms == null ? true : try(var.access_logs.cloudwatch.enable_metric_filters, false)
    error_message = "Alarms require access_logs.cloudwatch with enable_metric_filters, as Verified Access publishes no metrics of its own."
  }

  # V36: the thresholds are positive and the alarm windows are within the seven days CloudWatch evaluates
  validation {
    condition = var.alarms == null ? true : (
      var.alarms.thresholds.http_504 >= 1 &&
      var.alarms.thresholds.access_denied >= 1 &&
      var.alarms.thresholds.logging_stopped_hours >= 1 && var.alarms.thresholds.logging_stopped_hours <= 168 &&
      var.alarms.thresholds.no_access_allowed_hours >= 1 && var.alarms.thresholds.no_access_allowed_hours <= 168
    )
    error_message = "The alarms.thresholds must be at least 1, and the hour thresholds at most 168 (seven days)."
  }

  # V37: the topic, key and recipients are well formed
  validation {
    condition = var.alarms == null ? true : (
      (var.alarms.sns_topic_arn == null ? true : can(regex("^arn:aws[a-z-]*:sns:", var.alarms.sns_topic_arn))) &&
      (var.alarms.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:", var.alarms.kms_key_arn))) &&
      alltrue([for address in var.alarms.email_addresses : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", address))])
    )
    error_message = "The alarms.sns_topic_arn must be an SNS topic ARN, alarms.kms_key_arn a KMS key ARN and alarms.email_addresses valid email addresses."
  }

  # V38: the key only applies to a topic the module creates, and is either created or supplied
  validation {
    condition = var.alarms == null ? true : (
      !(var.alarms.create_kms_key && var.alarms.kms_key_arn != null) &&
      (var.alarms.sns_topic_arn == null || (var.alarms.kms_key_arn == null && !var.alarms.create_kms_key))
    )
    error_message = "Set at most one of alarms.create_kms_key and alarms.kms_key_arn, and neither when alarms.sns_topic_arn is set, as the key only applies to the topic created by the module."
  }
}

variable "allowed_egress_cidr_blocks" {
  description = "The CIDR blocks endpoint security groups may send traffic to when the target range cannot be derived (load-balancer, network-interface and rds endpoints)"
  type        = list(string)
  default     = ["10.0.0.0/8"]

  validation {
    condition     = alltrue([for cidr in var.allowed_egress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All allowed_egress_cidr_blocks must be valid CIDR blocks."
  }
}

variable "certificate" {
  description = "An optional wildcard public certificate (*.<domain_name>) for http and https endpoints that set no domain_certificate_arn; publish the certificate_validation_records output in the domain's DNS"
  type = object({
    ## The domain the certificate covers, e.g. example.com requests *.example.com
    domain_name = string
    ## Wait for the certificate to be issued before creating the endpoints that use it; publish the validation records first
    wait_for_validation = optional(bool, false)
  })
  default = null

  # V34: the domain is a plain domain name, the module adds the wildcard
  validation {
    condition     = var.certificate == null ? true : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.certificate.domain_name))
    error_message = "The certificate.domain_name must be a lowercase domain name without a wildcard, e.g. example.com."
  }
}

variable "cidr_endpoints_custom_subdomain" {
  description = "An optional custom subdomain for CIDR endpoints; delegate it to the name servers exported by the module"
  type        = string
  default     = null
}

variable "dashboard" {
  description = "An optional CloudWatch dashboard (verified-access-<name>) showing access decisions, HTTP errors, load balancer health and who is connecting; null disables it. Requires CloudWatch access logs with metric filters"
  type = object({
    ## The period in seconds of the metric widgets
    period = optional(number, 300)
  })
  default = null

  # V39: the dashboard shows the log derived metrics and queries the access logs
  validation {
    condition     = var.dashboard == null ? true : try(var.access_logs.cloudwatch.enable_metric_filters, false)
    error_message = "The dashboard requires access_logs.cloudwatch with enable_metric_filters, as Verified Access publishes no metrics of its own."
  }

  # V40: the period is one CloudWatch accepts for metric widgets
  validation {
    condition     = var.dashboard == null ? true : contains([60, 300, 900, 3600, 21600, 86400], var.dashboard.period)
    error_message = "The dashboard.period must be 60, 300, 900, 3600, 21600 or 86400 seconds."
  }
}

variable "description" {
  description = "The description of the Verified Access instance"
  type        = string
  default     = null
}

variable "device_trust_provider" {
  description = "An optional device posture trust provider; null disables device posture"
  type = object({
    ## The type of device trust provider (crowdstrike, jamf, jumpcloud)
    type = string
    ## The Cedar context key for the provider, defaults to the type, e.g. context.crowdstrike
    policy_reference_name = optional(string, null)
    ## The tenant id of the device provider application
    tenant_id = string
    ## CrowdStrike only: the minimum assessment.overall score (1-100) for sensitive endpoints
    crowdstrike_min_score = optional(number, 50)
    ## Jamf only: the risk levels permitted for sensitive endpoints
    jamf_allowed_risk = optional(list(string), ["LOW", "SECURE"])
  })
  default = null

  # V5: the device provider type is supported by Verified Access
  validation {
    condition     = var.device_trust_provider == null ? true : contains(["crowdstrike", "jamf", "jumpcloud"], var.device_trust_provider.type)
    error_message = "The device_trust_provider.type must be crowdstrike, jamf or jumpcloud."
  }

  # V3 (device): the policy reference name is a valid Cedar identifier
  validation {
    condition = var.device_trust_provider == null ? true : (
      var.device_trust_provider.policy_reference_name == null ? true : can(regex("^[a-z][a-z0-9_]{0,31}$", var.device_trust_provider.policy_reference_name))
    )
    error_message = "The device_trust_provider.policy_reference_name must start with a lowercase letter and contain only lowercase letters, digits and underscores (max 32)."
  }

  # V6: the CrowdStrike score is within the range CrowdStrike reports
  validation {
    condition = var.device_trust_provider == null ? true : (
      var.device_trust_provider.crowdstrike_min_score >= 1 && var.device_trust_provider.crowdstrike_min_score <= 100
    )
    error_message = "The device_trust_provider.crowdstrike_min_score must be between 1 and 100."
  }

  # V7: the Jamf risk levels are ones Jamf reports
  validation {
    condition = var.device_trust_provider == null ? true : (
      length(var.device_trust_provider.jamf_allowed_risk) > 0 && alltrue([
        for risk in var.device_trust_provider.jamf_allowed_risk : contains(["HIGH", "MEDIUM", "LOW", "SECURE", "NOT_APPLICABLE"], risk)
      ])
    )
    error_message = "The device_trust_provider.jamf_allowed_risk must be a non-empty list of HIGH, MEDIUM, LOW, SECURE or NOT_APPLICABLE."
  }
}

variable "groups" {
  description = "The Verified Access groups keyed by name; each group holds its access policy and the endpoints it protects"
  type = map(object({
    ## The description of the group
    description = optional(string, null)
    ## The structured access policy (preferred), rendered to Cedar by the module
    policy = optional(object({
      # The identity groups permitted: Identity Center group ids, or OIDC group names
      identity_groups = list(string)
      # The team accountable for this access
      owner = string
      # Why this access exists
      justification = string
    }), null)
    ## Escape hatch: a raw Cedar policy, e.g. file("policies/raw/<name>.cedar"); requires security review
    raw_policy = optional(object({
      # The Cedar policy text
      cedar = string
      # The team accountable for this access
      owner = string
      # Why the structured policy cannot express this access
      justification = string
    }), null)
    ## The endpoints in this group keyed by name; names must be unique across all groups
    endpoints = optional(map(object({
      # The endpoint type (load-balancer, network-interface, cidr, rds); cidr endpoints only reach addresses in the
      # endpoint's own VPC, so reach services across a transit gateway with a load-balancer endpoint and an NLB
      # with IP targets
      type = string
      # The description of the endpoint
      description = optional(string, null)
      # The protocol (http, https, tcp); cidr and rds endpoints are tcp only
      protocol = optional(string, "tcp")
      # Sensitive endpoints receive an endpoint policy requiring device posture
      sensitive = optional(bool, false)
      # The port for http/https and rds endpoints
      port = optional(number, null)
      # The port ranges for tcp endpoints
      port_ranges = optional(list(object({
        from_port = number
        to_port   = number
      })), [])
      # The load balancer arn (load-balancer endpoints)
      load_balancer_arn = optional(string, null)
      # The IPv4 addresses of the service across the transit gateway (load-balancer endpoints with topology hub); the
      # module creates a listener and target group on the central load balancer instead of using load_balancer_arn
      targets = optional(list(string), [])
      # The network interface id (network-interface endpoints)
      network_interface_id = optional(string, null)
      # The CIDR block (cidr endpoints)
      cidr = optional(string, null)
      # The RDS target (rds endpoints); set exactly one of the arns
      rds = optional(object({
        instance_arn = optional(string, null)
        cluster_arn  = optional(string, null)
        proxy_arn    = optional(string, null)
        endpoint     = string
      }), null)
      # The public DNS name users browse to (http/https endpoints only)
      application_domain = optional(string, null)
      # The public ACM certificate for the application domain (http/https endpoints only)
      domain_certificate_arn = optional(string, null)
      # The prefix for the generated endpoint domain, defaults to the endpoint name
      endpoint_domain_prefix = optional(string, null)
      # Override the subnets for this endpoint, defaults to var.subnet_ids
      subnet_ids = optional(list(string), null)
      # Additional security groups to attach to the endpoint
      security_group_ids = optional(list(string), [])
      # Override the CIDR blocks the endpoint security group may send to
      egress_cidr_blocks = optional(list(string), null)
      # Escape hatch: a raw Cedar endpoint policy; requires security review
      raw_policy = optional(object({
        cedar         = string
        owner         = string
        justification = string
      }), null)
    })), {})
  }))
  default = {}

  # V9: group and endpoint names are lowercase kebab-case
  validation {
    condition = alltrue(concat(
      [for name in keys(var.groups) : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name))],
      [for name in flatten([for group in values(var.groups) : keys(group.endpoints)]) : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name))],
    ))
    error_message = "Group and endpoint names must be lowercase alphanumeric and hyphens, starting and ending with an alphanumeric character (max 63)."
  }

  # V10: each group has exactly one of policy or raw_policy
  validation {
    condition     = alltrue([for group in values(var.groups) : (group.policy != null) != (group.raw_policy != null)])
    error_message = "Each group must set exactly one of policy or raw_policy."
  }

  # V11: a structured policy names at least one identity group (prevents an unscoped permit)
  validation {
    condition     = alltrue([for group in values(var.groups) : group.policy == null ? true : length(group.policy.identity_groups) > 0])
    error_message = "A group policy must list at least one identity group; an empty list would permit anyone who can sign in."
  }

  # V11 (Identity Center): identity groups are group ids, not display names
  validation {
    condition = var.user_trust_provider.type != "iam-identity-center" ? true : alltrue([
      for group in values(var.groups) : group.policy == null ? true : alltrue([
        for id in group.policy.identity_groups : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
      ])
    ])
    error_message = "With IAM Identity Center, identity_groups must be group ids (e.g. 11111111-1111-1111-1111-111111111111), not display names."
  }

  # V12: every policy has an accountable owner and a single-line justification
  validation {
    condition = alltrue([
      for policy in flatten([
        [for group in values(var.groups) : [for policy in [group.policy, group.raw_policy] : policy if policy != null]],
        [for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.raw_policy if endpoint.raw_policy != null],
        ]) : (
        length(trimspace(policy.owner)) > 0 &&
        length(trimspace(policy.justification)) >= 10 &&
        !strcontains(policy.owner, "\n") &&
        !strcontains(policy.justification, "\n")
      )
    ])
    error_message = "Every policy needs a non-empty owner and a single-line justification of at least 10 characters."
  }

  # V12 (raw): raw Cedar is not empty
  validation {
    condition = alltrue(concat(
      [for group in values(var.groups) : group.raw_policy == null ? true : length(trimspace(group.raw_policy.cedar)) > 0],
      [for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.raw_policy == null ? true : length(trimspace(endpoint.raw_policy.cedar)) > 0],
    ))
    error_message = "A raw_policy must contain Cedar policy text."
  }

  # V13: the endpoint type and protocol are supported
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      contains(["load-balancer", "network-interface", "cidr", "rds"], endpoint.type) && contains(["http", "https", "tcp"], endpoint.protocol)
    ])
    error_message = "Endpoint type must be load-balancer, network-interface, cidr or rds, and protocol must be http, https or tcp."
  }

  # V13: cidr and rds endpoints are tcp only
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      contains(["cidr", "rds"], endpoint.type) ? endpoint.protocol == "tcp" : true
    ])
    error_message = "cidr and rds endpoints only support the tcp protocol."
  }

  # V13: the target matching the endpoint type is set
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : (
        endpoint.type == "load-balancer" ? endpoint.load_balancer_arn != null || length(endpoint.targets) > 0 :
        endpoint.type == "network-interface" ? endpoint.network_interface_id != null :
        endpoint.type == "cidr" ? endpoint.cidr != null :
        endpoint.type == "rds" ? endpoint.rds != null : true
      )
    ])
    error_message = "Each endpoint must set the target for its type: load_balancer_arn (or targets with topology hub), network_interface_id, cidr or rds."
  }

  # V13: cidr endpoints use a valid CIDR block
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      endpoint.type == "cidr" ? can(cidrhost(endpoint.cidr, 0)) : true
    ])
    error_message = "The cidr of a cidr endpoint must be a valid CIDR block."
  }

  # V13: rds endpoints set exactly one of the instance, cluster or proxy arn
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      endpoint.rds == null ? true : length([for arn in [endpoint.rds.instance_arn, endpoint.rds.cluster_arn, endpoint.rds.proxy_arn] : arn if arn != null]) == 1
    ])
    error_message = "An rds endpoint must set exactly one of instance_arn, cluster_arn or proxy_arn."
  }

  # V13: ports are present for the protocol and within range
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : (
        (endpoint.type == "rds" || endpoint.protocol != "tcp" ? endpoint.port != null : length(endpoint.port_ranges) > 0) &&
        (endpoint.port == null ? true : endpoint.port >= 1 && endpoint.port <= 65535) &&
        alltrue([for range in endpoint.port_ranges : range.from_port >= 1 && range.to_port <= 65535 && range.from_port <= range.to_port])
      )
    ])
    error_message = "Set port for http, https and rds endpoints and port_ranges for tcp endpoints; ports must be 1-65535 with from_port <= to_port."
  }

  # V14: http and https endpoints need a public domain and certificate
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      endpoint.protocol == "tcp" ? true : endpoint.application_domain != null && (endpoint.domain_certificate_arn != null || var.certificate != null)
    ])
    error_message = "http and https endpoints require application_domain and either domain_certificate_arn (a public ACM certificate) or the module certificate."
  }

  # V15: sensitive endpoints require a device trust provider (fail closed)
  validation {
    condition = var.device_trust_provider != null ? true : !anytrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.sensitive
    ])
    error_message = "Endpoints marked sensitive require a device_trust_provider; configure one or remove the sensitive flag."
  }

  # V16: endpoint names are unique across all groups
  validation {
    condition     = length(flatten([for group in values(var.groups) : keys(group.endpoints)])) == length(distinct(flatten([for group in values(var.groups) : keys(group.endpoints)])))
    error_message = "Endpoint names must be unique across all groups."
  }

  # V24: targets are IPv4 addresses
  validation {
    condition = alltrue([
      for target in flatten([for group in values(var.groups) : [for endpoint in values(group.endpoints) : endpoint.targets]]) :
      can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$", target))
    ])
    error_message = "Endpoint targets must be IPv4 addresses, e.g. 10.50.0.10."
  }

  # V25: targets are reached through the central load balancer, which only exists with topology hub
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      length(endpoint.targets) == 0 || (var.topology == "hub" && endpoint.type == "load-balancer")
    ])
    error_message = "Endpoint targets are only supported on load-balancer endpoints with topology hub."
  }

  # V26: a load-balancer endpoint uses either its own load balancer or the central one, not both
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      endpoint.load_balancer_arn == null || length(endpoint.targets) == 0
    ])
    error_message = "A load-balancer endpoint must set either load_balancer_arn or targets, not both."
  }

  # V27: a tcp endpoint with targets maps to exactly one listener port
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      length(endpoint.targets) == 0 || endpoint.protocol != "tcp" || (length(endpoint.port_ranges) == 1 && try(endpoint.port_ranges[0].from_port == endpoint.port_ranges[0].to_port, false))
    ])
    error_message = "A tcp endpoint with targets must have exactly one port range with from_port equal to to_port, which becomes its listener port."
  }

  # V28: each endpoint with targets has its own listener port on the central load balancer
  validation {
    condition = length([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint if length(endpoint.targets) > 0
      ]) == length(distinct([
        for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
        endpoint.protocol == "tcp" ? try(endpoint.port_ranges[0].from_port, 0) : endpoint.port if length(endpoint.targets) > 0
    ]))
    error_message = "Endpoints with targets must use different ports, as each has its own listener on the central load balancer."
  }

  # V29: the target group name va-<name>-<endpoint> fits in 32 characters, and nlb is reserved for the load
  # balancer security group (verified-access-<name>-nlb)
  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : [
        for name, endpoint in group.endpoints : length(var.name) + length(name) <= 28 && name != "nlb" if length(endpoint.targets) > 0
      ]
    ]))
    error_message = "Endpoints with targets must be named other than nlb, and the deployment name plus the endpoint name must be at most 28 characters, as their target group is named va-<name>-<endpoint> (max 32)."
  }

  # V30: endpoints with targets use the module subnets, which the central load balancer accepts traffic from
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      length(endpoint.targets) == 0 || endpoint.subnet_ids == null
    ])
    error_message = "Endpoints with targets cannot override subnet_ids; they use var.subnet_ids, which hold the central load balancer."
  }

  # V31: the module certificate covers the application domain of the endpoints that use it
  validation {
    condition = var.certificate == null ? true : alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : (
        endpoint.protocol == "tcp" || endpoint.domain_certificate_arn != null || endpoint.application_domain == null ? true : (
          endswith(lower(endpoint.application_domain), format(".%s", var.certificate.domain_name)) &&
          !strcontains(trimsuffix(lower(endpoint.application_domain), format(".%s", var.certificate.domain_name)), ".")
        )
      )
    ])
    error_message = "An http or https endpoint using the module certificate must have an application_domain one level below certificate.domain_name, e.g. app.example.com for example.com."
  }
}

variable "kms_key_arn" {
  description = "An optional customer managed KMS key used to encrypt Verified Access trust providers, groups and endpoints"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be a KMS key ARN."
  }
}

variable "load_balancer" {
  description = "Settings for the central internal network load balancer created with topology hub, which reaches services across the transit gateway"
  type = object({
    ## Fixed private IPv4 addresses for the load balancer keyed by subnet id, so firewalls and tenants can allow exact
    ## addresses; changing them replaces the load balancer
    private_ips = optional(map(string), {})
    ## Protect the load balancer from deletion
    enable_deletion_protection = optional(bool, false)
    ## The idle timeout in seconds of the TCP listeners (60-6000); keep SSH sessions alive with ServerAliveInterval
    tcp_idle_timeout_seconds = optional(number, 350)
  })
  default = {}

  # V32: the fixed addresses are IPv4 addresses in the module subnets
  validation {
    condition = alltrue([
      for subnet_id, address in var.load_balancer.private_ips :
      contains(var.subnet_ids, subnet_id) && can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$", address))
    ])
    error_message = "The load_balancer.private_ips must be keyed by subnet ids from var.subnet_ids, with IPv4 addresses as values."
  }

  # V33: the idle timeout is within the range Network Load Balancers support
  validation {
    condition     = var.load_balancer.tcp_idle_timeout_seconds >= 60 && var.load_balancer.tcp_idle_timeout_seconds <= 6000
    error_message = "The load_balancer.tcp_idle_timeout_seconds must be between 60 and 6000."
  }
}

variable "metric_stream" {
  description = "An optional CloudWatch metric stream of the log derived metrics (and, with topology hub, the AWS/NetworkELB namespace) to a Kinesis Data Firehose delivery stream, e.g. for an external observability platform; null disables it"
  type = object({
    ## The ARN of the Kinesis Data Firehose delivery stream receiving the metrics
    firehose_arn = string
    ## The ARN of the IAM role CloudWatch assumes to write to the delivery stream
    role_arn = string
    ## The output format (json, opentelemetry0.7, opentelemetry1.0)
    output_format = optional(string, "opentelemetry1.0")
  })
  default = null

  # V41: the stream carries the log derived metrics; an empty include filter would stream every metric
  validation {
    condition     = var.metric_stream == null ? true : try(var.access_logs.cloudwatch.enable_metric_filters, false)
    error_message = "The metric stream requires access_logs.cloudwatch with enable_metric_filters, as Verified Access publishes no metrics of its own."
  }

  # V42: the delivery stream, role and output format are well formed
  validation {
    condition = var.metric_stream == null ? true : (
      can(regex("^arn:aws[a-z-]*:firehose:", var.metric_stream.firehose_arn)) &&
      can(regex("^arn:aws[a-z-]*:iam::", var.metric_stream.role_arn)) &&
      contains(["json", "opentelemetry0.7", "opentelemetry1.0"], var.metric_stream.output_format)
    )
    error_message = "The metric_stream needs a Firehose delivery stream ARN, an IAM role ARN and an output_format of json, opentelemetry0.7 or opentelemetry1.0."
  }
}

variable "name" {
  description = "The name of the Verified Access deployment, used to name and tag all resources, e.g. production"
  type        = string

  # V1: the name is safe to use in AWS resource names
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.name))
    error_message = "The name must be lowercase alphanumeric and hyphens, starting and ending with an alphanumeric character (max 32)."
  }
}

variable "oidc_client_secret" {
  description = "The OAuth client secret for an OIDC user trust provider; source it from a secret store, never from tfvars"
  type        = string
  default     = null
  sensitive   = true

  # V4: an OIDC provider needs a client secret
  validation {
    condition     = var.user_trust_provider.type != "oidc" ? true : var.oidc_client_secret != null
    error_message = "The oidc_client_secret is required when user_trust_provider.type is oidc."
  }
}

variable "subnet_ids" {
  description = "The dedicated subnets for the Verified Access endpoint network interfaces, one per availability zone"
  type        = list(string)

  # V8: at least one subnet is provided
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet id is required."
  }
}

variable "tags" {
  description = "The tags to apply to all resources"
  type        = map(string)
}

variable "topology" {
  description = "The network topology: single-vpc (endpoints reach services in their own VPC) or hub (a central internal network load balancer reaches services in spoke VPCs across a transit gateway)"
  type        = string
  default     = "single-vpc"

  # V22: the topology is supported
  validation {
    condition     = contains(["hub", "single-vpc"], var.topology)
    error_message = "The topology must be hub or single-vpc."
  }

  # V23: the load balancer name verified-access-<name> fits in 32 characters
  validation {
    condition     = var.topology != "hub" || length(var.name) <= 16
    error_message = "With topology hub the name must be at most 16 characters, as the load balancer is named verified-access-<name> (max 32)."
  }
}

variable "user_trust_provider" {
  description = "The user identity trust provider, IAM Identity Center or an OIDC identity provider"
  type = object({
    ## The type of user trust provider (iam-identity-center, oidc)
    type = string
    ## The Cedar context key for the provider, used by both the trust provider and the rendered policies
    policy_reference_name = optional(string, "idc")
    ## Require a verified email address (IAM Identity Center only); off by default, as directories that do not
    ## verify emails (Identity Center reports email.verified = false) would deny every user
    require_verified_email = optional(bool, false)
    ## The OIDC settings, required when type is oidc
    oidc = optional(object({
      # The OIDC issuer identifier
      issuer = string
      # The OIDC authorization endpoint
      authorization_endpoint = string
      # The OIDC token endpoint
      token_endpoint = string
      # The OIDC user info endpoint
      user_info_endpoint = string
      # The OAuth client id; the secret is passed in oidc_client_secret
      client_id = string
      # The space delimited scopes; offline_access enables refresh tokens
      scope = optional(string, "openid email groups offline_access")
      # The public signing key endpoint, enables native application (Connectivity Client) access
      public_signing_key_endpoint = optional(string, null)
    }), null)
  })

  # V2: the user provider type is supported by Verified Access
  validation {
    condition     = contains(["iam-identity-center", "oidc"], var.user_trust_provider.type)
    error_message = "The user_trust_provider.type must be iam-identity-center or oidc."
  }

  # V3: the policy reference name is a valid Cedar identifier
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,31}$", var.user_trust_provider.policy_reference_name))
    error_message = "The user_trust_provider.policy_reference_name must start with a lowercase letter and contain only lowercase letters, digits and underscores (max 32)."
  }

  # V4: the OIDC settings are present exactly when the type is oidc
  validation {
    condition     = (var.user_trust_provider.type == "oidc") == (var.user_trust_provider.oidc != null)
    error_message = "Set user_trust_provider.oidc when type is oidc, and only then."
  }
}

variable "vpc_id" {
  description = "The VPC containing the dedicated Verified Access subnets, used for the endpoint security groups"
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "The vpc_id must be a VPC id, e.g. vpc-0123456789abcdef0."
  }
}

variable "waf" {
  description = "An optional AWS WAF web ACL for the instance, either an existing one or one created by the module with AWS managed rule groups; null disables it. WAF applies to http and https endpoints only, and with IAM Identity Center it inspects requests before sign-in"
  type = object({
    ## The ARN of an existing regional web ACL to associate
    web_acl_arn = optional(string, null)
    ## Create a regional web ACL (verified-access-<name>) with the AWS common, known bad inputs and IP reputation rule groups
    create = optional(bool, false)
  })
  default = null

  # V43: exactly one source of web ACL
  validation {
    condition     = var.waf == null ? true : (var.waf.web_acl_arn != null) != var.waf.create
    error_message = "The waf must set exactly one of web_acl_arn or create = true."
  }

  # V44: the web ACL is a regional WAFv2 web ACL
  validation {
    condition     = var.waf == null ? true : var.waf.web_acl_arn == null || can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.waf.web_acl_arn))
    error_message = "The waf.web_acl_arn must be a regional WAFv2 web ACL ARN."
  }
}
