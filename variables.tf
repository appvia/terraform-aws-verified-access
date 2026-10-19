variable "access_logs" {
  description = "Access logging configuration for the Verified Access instance; null disables logging (a check warns). Set for every live environment"
  type = object({
    ## The OCSF log version (ocsf-0.1, ocsf-1.0.0-rc.2); rc.2 is required for trust context and TCP endpoints
    log_version = optional(string, "ocsf-1.0.0-rc.2")
    ## Include identity and device trust context in the logs; this is personal data, so it is opt-in
    include_trust_context = optional(bool, false)
    ## CloudWatch Logs destination: a log group the module creates (the default, so retention is always bounded), or an
    ## existing one (create = false and log_group_name)
    cloudwatch = optional(object({
      # Create the log group; false delivers to an existing log group (log_group_name), whose retention and
      # encryption are then owned elsewhere, and retention_in_days and kms_key_arn are ignored
      create = optional(bool, true)
      # The name of the existing log group; with create, the name of the log group to create, defaulting to
      # /aws/<name_prefix>/<name>
      log_group_name = optional(string, null)
      # The number of days to retain the logs
      retention_in_days = optional(number, 90)
      # An optional customer managed KMS key used to encrypt the log group; its key policy must permit
      # logs.<region>.amazonaws.com
      kms_key_arn = optional(string, null)
      # Instead of kms_key_arn: create a customer managed KMS key (alias/<name_prefix>-<name>-access-logs, rotation
      # on) encrypting the created log group, usable only by CloudWatch Logs for that log group
      create_kms_key = optional(bool, false)
      # The log derived metrics to create, by key of the metrics output: access-allowed, access-denied, http-504 and
      # http-5xx; null creates them all, [] none. Alarms, the dashboard and the metric stream need the ones they use
      metric_filters = optional(list(string), null)
      # Create the saved Logs Insights queries who-is-connecting and denied-requests
      create_queries = optional(bool, true)
    }), null)
    ## S3 destination: an existing bucket (bucket_name, e.g. in the log archive account, carrying its own retention and
    ## object lock), or one the module creates in this account (create = true)
    s3 = optional(object({
      # Create the bucket, with versioning, encryption, a public access block, bucket owner enforced ownership, a
      # TLS only policy permitting Verified Access log delivery, a lifecycle expiry and optional object lock
      create = optional(bool, false)
      # The name of the existing bucket; with create, the name of the bucket to create, defaulting to
      # <name_prefix>-<name>-access-logs-<account id>
      bucket_name = optional(string, null)
      # The account id that owns an existing bucket, required when the bucket is in another account
      bucket_owner = optional(string, null)
      # An optional prefix for the log objects
      prefix = optional(string, null)
      # Created bucket only: the days after which log objects expire (and their old versions a day later)
      retention_days = optional(number, 365)
      # Created bucket only: S3 Object Lock default retention, making each log object undeletable for days. Object
      # Lock can only be enabled when the bucket is created and never turned off; in COMPLIANCE mode nobody, not even
      # the root user, can delete a locked object or the bucket until the retention ends
      object_lock = optional(object({
        ## The retention mode, COMPLIANCE or GOVERNANCE (users with s3:BypassGovernanceRetention may delete)
        mode = optional(string, "COMPLIANCE")
        ## The days each object is locked for
        days = number
      }), null)
      # Created bucket only: a customer managed KMS key (SSE-KMS) for the log objects, defaulting to SSE-S3; its key
      # policy must permit delivery.logs.amazonaws.com
      kms_key_arn = optional(string, null)
      # Created bucket only: delete the bucket on destroy even when it holds log objects (locked objects still block it)
      force_destroy = optional(bool, false)
    }), null)
    ## Kinesis Data Firehose destination, e.g. for a third party SIEM: an existing delivery stream
    ## (delivery_stream_name), or one the module creates in this account (create = true) writing to an S3 bucket
    firehose = optional(object({
      # Create the delivery stream, with the IAM role it writes to destination_bucket_arn with
      create = optional(bool, false)
      # The name of the existing delivery stream; with create, the name of the stream to create, defaulting to
      # <name_prefix>-<name>-access-logs
      delivery_stream_name = optional(string, null)
      # Created stream only, and required with it: the ARN of the S3 bucket the delivery stream writes to; a bucket in
      # another account must permit the delivery stream role (output access_log_firehose_role_arn) in its bucket policy
      destination_bucket_arn = optional(string, null)
      # Created stream only: an optional prefix for the delivered objects
      prefix = optional(string, null)
      # Created stream only: the seconds the delivery stream buffers before writing (0-900)
      buffering_interval = optional(number, 300)
      # Created stream only: the MiB the delivery stream buffers before writing (1-128)
      buffering_size = optional(number, 5)
      # Created stream only: an optional customer managed KMS key encrypting the delivered objects (SSE-KMS); the role
      # may use it via S3
      kms_key_arn = optional(string, null)
    }), null)
  })
  default = null

  # V17: at least one destination is configured
  validation {
    condition = var.access_logs == null ? true : (
      var.access_logs.cloudwatch != null || var.access_logs.s3 != null || var.access_logs.firehose != null
    )
    error_message = "When access_logs is set, at least one of cloudwatch, s3 or firehose must be configured."
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

  # V60: an existing log group is named, as the module cannot derive it
  validation {
    condition = var.access_logs == null ? true : (
      var.access_logs.cloudwatch == null ? true : var.access_logs.cloudwatch.create || var.access_logs.cloudwatch.log_group_name != null
    )
    error_message = "Set access_logs.cloudwatch.log_group_name when create is false, as the module delivers to that existing log group."
  }

  # V75 (logging): the logging configuration of an existing instance is owned elsewhere (validated here, as
  # existing_instance cannot read access_logs without a validation cycle through groups)
  validation {
    condition     = var.access_logs == null || var.existing_instance == null
    error_message = "With existing_instance, leave access_logs unset (and with it alarms, dashboard and metric_stream): the instance's logging configuration is owned elsewhere."
  }

  # V65: the S3 bucket is either created or an existing one named, and a created bucket is in this account
  validation {
    condition = try(var.access_logs.s3, null) == null ? true : (
      var.access_logs.s3.create ? var.access_logs.s3.bucket_owner == null : var.access_logs.s3.bucket_name != null
    )
    error_message = "Set access_logs.s3.bucket_name for an existing bucket, or create = true for one the module creates (without bucket_owner, as it is created in this account)."
  }

  # V66: the created bucket's settings are valid, and only set when the module creates the bucket
  validation {
    condition = try(var.access_logs.s3, null) == null ? true : (
      var.access_logs.s3.create ? (
        var.access_logs.s3.retention_days >= 1 &&
        (var.access_logs.s3.object_lock == null ? true : (
          contains(["COMPLIANCE", "GOVERNANCE"], var.access_logs.s3.object_lock.mode) &&
          var.access_logs.s3.object_lock.days >= 1 && var.access_logs.s3.object_lock.days <= var.access_logs.s3.retention_days
        )) &&
        (var.access_logs.s3.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:", var.access_logs.s3.kms_key_arn)))
      ) : var.access_logs.s3.object_lock == null && var.access_logs.s3.kms_key_arn == null && !var.access_logs.s3.force_destroy
    )
    error_message = "With access_logs.s3.create, retention_days must be at least 1, object_lock a mode of COMPLIANCE or GOVERNANCE with days between 1 and retention_days, and kms_key_arn a KMS key ARN; object_lock, kms_key_arn and force_destroy only apply to a bucket the module creates."
  }

  # V67: the default name of the created bucket, <name_prefix>-<name>-access-logs-<account id>, fits in 63 characters
  # and a supplied name is a valid bucket name
  validation {
    condition = !try(var.access_logs.s3.create, false) ? true : (
      var.access_logs.s3.bucket_name == null
      ? length(var.name_prefix) + length(var.name) <= 37
      : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_logs.s3.bucket_name))
    )
    error_message = "The created access log bucket is named <name_prefix>-<name>-access-logs-<account id> (max 63), so name_prefix plus name must be at most 37 characters; set access_logs.s3.bucket_name (a valid bucket name) otherwise."
  }

  # V68: the delivery stream is either created or an existing one named, like the S3 bucket (V65); a created stream
  # has a destination and buffering Firehose accepts, and its settings only apply to a stream the module creates
  validation {
    condition = try(var.access_logs.firehose, null) == null ? true : (
      (var.access_logs.firehose.delivery_stream_name == null ? true : can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.access_logs.firehose.delivery_stream_name))) &&
      (var.access_logs.firehose.create ? (
        can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_logs.firehose.destination_bucket_arn)) &&
        var.access_logs.firehose.buffering_interval >= 0 && var.access_logs.firehose.buffering_interval <= 900 &&
        var.access_logs.firehose.buffering_size >= 1 && var.access_logs.firehose.buffering_size <= 128 &&
        (var.access_logs.firehose.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:", var.access_logs.firehose.kms_key_arn)))
        ) : (
        var.access_logs.firehose.delivery_stream_name != null &&
        var.access_logs.firehose.destination_bucket_arn == null && var.access_logs.firehose.prefix == null && var.access_logs.firehose.kms_key_arn == null
      ))
    )
    error_message = "Set access_logs.firehose.delivery_stream_name for an existing delivery stream, or create = true with destination_bucket_arn (an S3 bucket ARN), buffering_interval 0-900, buffering_size 1-128 and kms_key_arn a KMS key ARN; destination_bucket_arn, prefix and kms_key_arn only apply to a stream the module creates, and delivery_stream_name is 1-64 letters, digits, underscores, dots and hyphens."
  }

  # V69: the log group key is either created or supplied, and only for a log group the module creates
  validation {
    condition = try(var.access_logs.cloudwatch, null) == null ? true : (
      !(var.access_logs.cloudwatch.create_kms_key && var.access_logs.cloudwatch.kms_key_arn != null) &&
      (var.access_logs.cloudwatch.create || !var.access_logs.cloudwatch.create_kms_key)
    )
    error_message = "Set at most one of access_logs.cloudwatch.create_kms_key and kms_key_arn, and create_kms_key only with create, as the key encrypts the log group the module creates."
  }

  # V80: the metric filters are log derived metrics the module defines
  validation {
    condition = try(var.access_logs.cloudwatch.metric_filters, null) == null ? true : alltrue([
      for key in var.access_logs.cloudwatch.metric_filters : contains(["access-allowed", "access-denied", "http-504", "http-5xx"], key)
    ])
    error_message = "The access_logs.cloudwatch.metric_filters entries must be access-allowed, access-denied, http-504 or http-5xx (null creates them all, [] none)."
  }
}

variable "alarms" {
  description = "Alarms on the log derived metrics, the central load balancer and changes made outside the pipeline; null disables alarms. Each alarm can be turned off or tuned in rules, and custom alarms added on any metric the module makes available (output metrics). The log derived alarms need CloudWatch access logs with their metric filters"
  type = object({
    ## Create the topic the alarms notify (<name_prefix>-<name>-alarms); false notifies the existing topic in
    ## sns_topic_arn instead
    create_sns_topic = optional(bool, true)
    ## The existing SNS topic to notify, with create_sns_topic = false
    sns_topic_arn = optional(string, null)
    ## Encrypt the created topic with a customer managed KMS key the module creates (<name_prefix>-<name>-alarms)
    create_kms_key = optional(bool, false)
    ## Encrypt the created topic with an existing customer managed KMS key; its key policy must permit CloudWatch and
    ## EventBridge. Leave both unset for an unencrypted topic
    kms_key_arn = optional(string, null)
    ## The email addresses subscribed to the topic; each recipient must confirm the subscription
    email_addresses = optional(list(string), [])
    ## The role the deployment pipeline assumes; when set, any other principal changing Verified Access raises an alarm
    ## (the changed-outside-pipeline rule)
    pipeline_role_name = optional(string, null)
    ## Additional ARNs notified on alarm and on recovery, e.g. an SNS topic subscribed by PagerDuty or AWS Chatbot
    additional_action_arns = optional(list(string), [])
    ## Per alarm settings, keyed by alarm: http-504, access-denied, logging-stopped, no-access-allowed,
    ## no-healthy-targets and unhealthy-targets (the last two apply to every endpoint with targets; key one endpoint as
    ## <endpoint>/no-healthy-targets to override it alone), and changed-outside-pipeline (enabled only). An alarm
    ## without a rule, or a setting left unset, keeps the module default (docs/operations.md, Alarms)
    rules = optional(map(object({
      # Create the alarm; false turns it off. Unset means on, or for an <endpoint>/<alarm> key the setting of <alarm>
      enabled = optional(bool, null)
      # The threshold compared with the statistic
      threshold = optional(number, null)
      # The period in seconds: 10, 30 or a multiple of 60
      period = optional(number, null)
      # The number of periods evaluated (period x evaluation_periods at most seven days)
      evaluation_periods = optional(number, null)
      # How missing data is treated: missing, ignore, breaching or notBreaching
      treat_missing_data = optional(string, null)
    })), {})
    ## Additional alarms keyed by name (lowercase kebab-case, alarm <name_prefix>-<name>-<key>), on any metric the module
    ## makes available, notifying the same actions
    custom = optional(map(object({
      # The metric, by key of the metrics output, e.g. access-denied or <endpoint>/unhealthy-host-count
      metric = string
      # The comparison: GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold or
      # LessThanOrEqualToThreshold
      comparison_operator = string
      # The threshold compared with the statistic
      threshold = number
      # The statistic: Sum, Average, Minimum, Maximum or SampleCount; the metrics output recommends one per metric
      statistic = optional(string, "Sum")
      # The period in seconds: 10, 30 or a multiple of 60
      period = optional(number, 300)
      # The number of periods evaluated (period x evaluation_periods at most seven days)
      evaluation_periods = optional(number, 1)
      # How missing data is treated: missing, ignore, breaching or notBreaching
      treat_missing_data = optional(string, "missing")
      # The alarm description, shown in the notification
      description = optional(string, null)
    })), {})
  })
  default = null

  # V35: the alarms on log derived metrics need CloudWatch access logs with the metric filters they watch: http-504,
  # access-denied and no-access-allowed (access-allowed) and custom alarms on those metrics their filter, and
  # logging-stopped and custom alarms on incoming-log-events or incoming-bytes the log group
  validation {
    condition = var.alarms == null ? true : alltrue([
      for metric in concat(
        [
          for alarm, metric in { "http-504" = "http-504", "access-denied" = "access-denied", "no-access-allowed" = "access-allowed", "logging-stopped" = "incoming-log-events" } :
          metric if try(var.alarms.rules[alarm].enabled, null) != false
        ],
        [for alarm in values(var.alarms.custom) : alarm.metric],
        ) : (
        contains(["incoming-log-events", "incoming-bytes"], metric) ? try(var.access_logs.cloudwatch, null) != null : (
          !contains(["access-allowed", "access-denied", "http-504", "http-5xx"], metric) ? true : try(
            var.access_logs.cloudwatch.metric_filters == null ? true : contains(var.access_logs.cloudwatch.metric_filters, metric), false
          )
        )
      )
    ])
    error_message = "Alarms on the log derived metrics need access_logs.cloudwatch with those metric filters (Verified Access publishes no metrics of its own): http-504 needs metric filter http-504, access-denied needs access-denied, no-access-allowed needs access-allowed and a custom alarm needs the filter of its metric; logging-stopped needs access_logs.cloudwatch. Add the filter to access_logs.cloudwatch.metric_filters, or turn the alarm off in alarms.rules."
  }

  # V36: the rule settings are ones CloudWatch accepts, with each alarm window (its period, or the default, times its
  # evaluation periods) within the seven days CloudWatch evaluates
  validation {
    condition = var.alarms == null ? true : alltrue([
      for key, rule in var.alarms.rules : key == "changed-outside-pipeline" || !contains(["http-504", "access-denied", "logging-stopped", "no-access-allowed", "no-healthy-targets", "unhealthy-targets"], element(split("/", key), length(split("/", key)) - 1)) ? true : (
        (rule.threshold == null ? true : rule.threshold >= 0) &&
        (rule.period == null ? true : contains([10, 30], rule.period) || (rule.period >= 60 && rule.period % 60 == 0)) &&
        (rule.evaluation_periods == null ? true : rule.evaluation_periods >= 1) &&
        (rule.treat_missing_data == null ? true : contains(["missing", "ignore", "breaching", "notBreaching"], rule.treat_missing_data)) &&
        coalesce(
          rule.period,
          try(var.alarms.rules[element(split("/", key), length(split("/", key)) - 1)].period, null),
          { "http-504" = 300, "access-denied" = 300, "logging-stopped" = 3600, "no-access-allowed" = 3600, "no-healthy-targets" = 60, "unhealthy-targets" = 60 }[element(split("/", key), length(split("/", key)) - 1)],
          ) * coalesce(
          rule.evaluation_periods,
          try(var.alarms.rules[element(split("/", key), length(split("/", key)) - 1)].evaluation_periods, null),
          { "http-504" = 1, "access-denied" = 1, "logging-stopped" = 1, "no-access-allowed" = 24, "no-healthy-targets" = 2, "unhealthy-targets" = 5 }[element(split("/", key), length(split("/", key)) - 1)],
        ) <= 604800
      )
    ])
    error_message = "The alarms.rules need a threshold of at least 0, period 10, 30 or a multiple of 60, evaluation_periods at least 1 with period x evaluation_periods at most seven days (604800 seconds), and treat_missing_data missing, ignore, breaching or notBreaching."
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
      (var.alarms.create_sns_topic || (var.alarms.kms_key_arn == null && !var.alarms.create_kms_key))
    )
    error_message = "Set at most one of alarms.create_kms_key and alarms.kms_key_arn, and neither with create_sns_topic = false, as the key only applies to the topic created by the module."
  }

  # V61: the rules are keyed by alarms the module creates, or by <endpoint>/<alarm> for the load balancer alarms
  validation {
    condition = var.alarms == null ? true : alltrue([
      for key in keys(var.alarms.rules) : contains(["http-504", "access-denied", "logging-stopped", "no-access-allowed", "no-healthy-targets", "unhealthy-targets", "changed-outside-pipeline"], key) || can(regex("^[a-z0-9][a-z0-9-]*/(no-healthy-targets|unhealthy-targets)$", key))
    ])
    error_message = "The alarms.rules keys must be http-504, access-denied, logging-stopped, no-access-allowed, no-healthy-targets, unhealthy-targets or changed-outside-pipeline, or <endpoint>/no-healthy-targets and <endpoint>/unhealthy-targets for one endpoint."
  }

  # V62: a per endpoint rule names an endpoint with targets on the central load balancer (topology hub), which is
  # what the load balancer alarms watch
  validation {
    condition = var.alarms == null ? true : alltrue([
      for key in keys(var.alarms.rules) : !strcontains(key, "/") ? true : var.topology == "hub" && contains(flatten([
        for group in values(var.groups) : [
          for name, endpoint in group.endpoints : name if endpoint.type == "load-balancer" && length(endpoint.targets) + length(endpoint.target_details) > 0
        ]
      ]), split("/", key)[0])
    ])
    error_message = "An alarms.rules key <endpoint>/<alarm> must name a load-balancer endpoint with targets (topology hub), as only those have load balancer alarms."
  }

  # V63: the additional actions are ARNs
  validation {
    condition     = var.alarms == null ? true : alltrue([for arn in var.alarms.additional_action_arns : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:", arn))])
    error_message = "The alarms.additional_action_arns must be ARNs, e.g. arn:aws:sns:eu-west-2:111111111111:pagerduty."
  }

  # V77: the changed-outside-pipeline rule is an EventBridge rule, not a metric alarm, so it can only be turned off
  validation {
    condition = try(var.alarms.rules["changed-outside-pipeline"], null) == null ? true : (
      var.alarms.rules["changed-outside-pipeline"].threshold == null &&
      var.alarms.rules["changed-outside-pipeline"].period == null &&
      var.alarms.rules["changed-outside-pipeline"].evaluation_periods == null &&
      var.alarms.rules["changed-outside-pipeline"].treat_missing_data == null
    )
    error_message = "The alarms.rules changed-outside-pipeline entry only takes enabled: it is an EventBridge rule on CloudTrail events (created when pipeline_role_name is set), not a metric alarm."
  }

  # V78: the custom alarms are named apart from the module's alarms and are ones CloudWatch accepts
  validation {
    condition = var.alarms == null ? true : alltrue([
      for key, alarm in var.alarms.custom : (
        can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", key)) &&
        !contains(["http-504", "access-denied", "logging-stopped", "no-access-allowed", "changed-outside-pipeline"], key) &&
        !can(regex("-(no-healthy-targets|unhealthy-targets)$", key)) &&
        contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], alarm.comparison_operator) &&
        contains(["Sum", "Average", "Minimum", "Maximum", "SampleCount"], alarm.statistic) &&
        (contains([10, 30], alarm.period) || (alarm.period >= 60 && alarm.period % 60 == 0)) &&
        alarm.evaluation_periods >= 1 && alarm.period * alarm.evaluation_periods <= 604800 &&
        contains(["missing", "ignore", "breaching", "notBreaching"], alarm.treat_missing_data)
      )
    ])
    error_message = "The alarms.custom keys must be lowercase kebab-case and not a module alarm name (http-504, access-denied, logging-stopped, no-access-allowed, changed-outside-pipeline, or ending in -no-healthy-targets or -unhealthy-targets); each needs a comparison_operator of GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold or LessThanOrEqualToThreshold, a statistic of Sum, Average, Minimum, Maximum or SampleCount, period 10, 30 or a multiple of 60, evaluation_periods at least 1 (period x evaluation_periods at most seven days) and treat_missing_data missing, ignore, breaching or notBreaching."
  }

  # V82: the alarm topic is either created or an existing one supplied
  validation {
    condition     = var.alarms == null ? true : var.alarms.create_sns_topic == (var.alarms.sns_topic_arn == null)
    error_message = "Set alarms.sns_topic_arn with create_sns_topic = false to notify an existing topic, or leave both at their defaults for a topic the module creates."
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

variable "create_kms_key" {
  description = "Instead of kms_key_arn: create a customer managed KMS key (alias/<name_prefix>-<name>, rotation on) encrypting the Verified Access trust providers, groups and endpoints, usable by Verified Access in this account. Deleting it makes their configuration unreadable, so it is deleted after a 30 day window"
  type        = bool
  default     = false
}

variable "dashboard" {
  description = "An optional CloudWatch dashboard (<name_prefix>-<name>) showing access decisions, HTTP errors, load balancer health and who is connecting; null disables it. Requires CloudWatch access logs with the metric filters access-allowed, access-denied, http-504 and http-5xx"
  type = object({
    ## The period in seconds of the metric widgets
    period = optional(number, 300)
  })
  default = null

  # V39: the dashboard shows the log derived metrics (all four) and queries the access logs
  validation {
    condition = var.dashboard == null ? true : try(
      var.access_logs.cloudwatch.metric_filters == null ? true : length(setsubtract(["access-allowed", "access-denied", "http-504", "http-5xx"], var.access_logs.cloudwatch.metric_filters)) == 0,
      false
    )
    error_message = "The dashboard requires access_logs.cloudwatch with the metric filters access-allowed, access-denied, http-504 and http-5xx (the default, metric_filters = null), as Verified Access publishes no metrics of its own."
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

variable "dns" {
  description = "An optional Route 53 public hosted zone where the module publishes the certificate validation records and the application CNAMEs (application_domain to endpoint domain) of http and https endpoints; null leaves DNS to the caller (outputs certificate_validation_records and application_domains)"
  type = object({
    ## The id of the public hosted zone of the application domains, e.g. Z0123456789ABCDEFGHIJ
    zone_id = string
    ## Publish the validation records of the module certificate
    create_validation_records = optional(bool, true)
    ## Publish a CNAME from each http and https endpoint application_domain to its endpoint domain
    create_application_records = optional(bool, true)
    ## The TTL in seconds of the records
    ttl = optional(number, 300)
  })
  default = null

  # V59: the zone is a Route 53 hosted zone id and the TTL a value Route 53 accepts
  validation {
    condition     = var.dns == null ? true : can(regex("^Z[A-Z0-9]{1,31}$", var.dns.zone_id)) && var.dns.ttl >= 0 && var.dns.ttl <= 2147483647
    error_message = "The dns.zone_id must be a Route 53 hosted zone id (e.g. Z0123456789ABCDEFGHIJ, without /hostedzone/) and dns.ttl between 0 and 2147483647."
  }
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

variable "existing_instance" {
  description = "An existing Verified Access instance to add the groups and endpoints to, instead of creating one; null (the default) creates the instance. The instance, its trust providers, logging and web ACL are then owned elsewhere, so user_trust_provider, device_trust_provider, the OIDC client secrets, access_logs (and with it alarms, dashboard and metric_stream), waf, fips_enabled, description and cidr_endpoints_custom_subdomain must be left unset; the settings below describe the attached trust providers so the module can render the policies"
  type = object({
    ## The id of the instance, e.g. vai-0123456789abcdef0
    id = string
    ## The type of the user trust provider attached to the instance (iam-identity-center, oidc), which decides how
    ## identity groups are rendered
    user_trust_provider_type = optional(string, "iam-identity-center")
    ## The Cedar context key (policy reference name) of the attached user trust provider, e.g. idc
    user_policy_reference_name = string
    ## OIDC only: the claim holding the user's groups, as in user_trust_provider.oidc.groups_claim
    user_groups_claim = optional(string, "groups")
    ## IAM Identity Center only: require a verified email address in every group policy, as in
    ## user_trust_provider.require_verified_email
    require_verified_email = optional(bool, false)
    ## The device trust provider attached to the instance, needed for sensitive endpoints; null when none is attached
    device_trust_provider = optional(object({
      # The type of device trust provider (crowdstrike, jamf, jumpcloud)
      type = string
      # The Cedar context key (policy reference name) of the attached provider, defaults to the type
      policy_reference_name = optional(string, null)
      # CrowdStrike only: the minimum assessment.overall score (1-100) for sensitive endpoints
      crowdstrike_min_score = optional(number, 50)
      # Jamf only: the risk levels permitted for sensitive endpoints
      jamf_allowed_risk = optional(list(string), ["LOW", "SECURE"])
    }), null)
  })
  default = null

  # V74: exactly one of a created instance (user_trust_provider) and an existing instance, named by its id
  validation {
    condition = (var.existing_instance == null) == (var.user_trust_provider != null) && (
      var.existing_instance == null ? true : can(regex("^vai-[0-9a-f]+$", var.existing_instance.id))
    )
    error_message = "Set exactly one of user_trust_provider (the module creates the instance) and existing_instance (an existing instance, id like vai-0123456789abcdef0)."
  }

  # V75: the instance level settings belong to whoever owns the existing instance
  validation {
    condition = var.existing_instance == null ? true : (
      var.device_trust_provider == null && var.oidc_client_secret == null && var.oidc_native_client_secret == null &&
      var.waf == null && !var.fips_enabled && var.description == null &&
      var.cidr_endpoints_custom_subdomain == null
    )
    error_message = "With existing_instance, leave device_trust_provider, oidc_client_secret, oidc_native_client_secret, waf, fips_enabled, description and cidr_endpoints_custom_subdomain unset: the instance, its trust providers, logging and web ACL are owned elsewhere. Describe an attached device provider in existing_instance.device_trust_provider."
  }

  # V76: the attached trust providers are described with values Verified Access and Cedar accept, as for the providers
  # the module creates (V2, V3, V5-V7, V51)
  validation {
    condition = var.existing_instance == null ? true : (
      contains(["iam-identity-center", "oidc"], var.existing_instance.user_trust_provider_type) &&
      can(regex("^[a-z][a-z0-9_]{0,31}$", var.existing_instance.user_policy_reference_name)) &&
      can(regex("^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$", var.existing_instance.user_groups_claim)) &&
      (var.existing_instance.device_trust_provider == null ? true : (
        contains(["crowdstrike", "jamf", "jumpcloud"], var.existing_instance.device_trust_provider.type) &&
        (var.existing_instance.device_trust_provider.policy_reference_name == null ? true : can(regex("^[a-z][a-z0-9_]{0,31}$", var.existing_instance.device_trust_provider.policy_reference_name))) &&
        var.existing_instance.device_trust_provider.crowdstrike_min_score >= 1 && var.existing_instance.device_trust_provider.crowdstrike_min_score <= 100 &&
        length(var.existing_instance.device_trust_provider.jamf_allowed_risk) > 0 && alltrue([
          for risk in var.existing_instance.device_trust_provider.jamf_allowed_risk : contains(["HIGH", "MEDIUM", "LOW", "SECURE", "NOT_APPLICABLE"], risk)
        ])
      ))
    )
    error_message = "The existing_instance needs user_trust_provider_type iam-identity-center or oidc, a user_policy_reference_name and optional device policy_reference_name of lowercase letters, digits and underscores (max 32), a user_groups_claim of letters, digits, underscores and dots, and a device_trust_provider type of crowdstrike, jamf or jumpcloud with crowdstrike_min_score 1-100 and jamf_allowed_risk from HIGH, MEDIUM, LOW, SECURE and NOT_APPLICABLE."
  }
}

variable "fips_enabled" {
  description = "Enable FIPS 140-2 validated endpoints on the Verified Access instance. Only supported in US, Canada and AWS GovCloud (US) regions (a check warns elsewhere); changing it replaces the instance and everything in it"
  type        = bool
  default     = false
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
    ## Tags merged over var.tags on the group and on every endpoint in it, e.g. a cost centre for chargeback
    tags = optional(map(string), {})
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
        ## The first port of the range
        from_port = number
        ## The last port of the range (the same as from_port for a single port)
        to_port = number
      })), [])
      # The load balancer arn (load-balancer endpoints)
      load_balancer_arn = optional(string, null)
      # The IPv4 addresses of the service across the transit gateway (load-balancer endpoints with topology hub); the
      # module creates a listener and target group on the central load balancer instead of using load_balancer_arn
      targets = optional(list(string), [])
      # Instead of targets: the service addresses with an optional per target port (defaults to the endpoint port)
      # and availability zone ("all" for addresses outside the load balancer VPC, or the zone name of an address
      # inside it)
      target_details = optional(list(object({
        ## The IPv4 address of the target
        ip = string
        ## The port of the target, defaults to the endpoint port
        port = optional(number, null)
        ## The availability zone of the target; all for addresses across a transit gateway
        availability_zone = optional(string, "all")
      })), [])
      # Hub only: the port of the listener on the central load balancer, which is also the port clients connect to
      # on the endpoint domain; defaults to the endpoint port. Set it to put several services on the same port (e.g.
      # SSH hosts on 22) behind the central load balancer: each keeps port_ranges (or port) as its service port
      listener_port = optional(number, null)
      # Hub only: the target group health check; defaults to TCP on the traffic port
      health_check = optional(object({
        ## The health check protocol (TCP, HTTP or HTTPS)
        protocol = optional(string, "TCP")
        ## The port checked, defaults to the port receiving traffic
        port = optional(string, "traffic-port")
        ## The path checked (HTTP and HTTPS health checks only)
        path = optional(string, null)
        ## Consecutive successes before a target is healthy (2-10)
        healthy_threshold = optional(number, 3)
        ## Consecutive failures before a target is unhealthy (2-10)
        unhealthy_threshold = optional(number, 3)
        ## The seconds between checks (5-300)
        interval = optional(number, 30)
      }), null)
      # Hub only: the seconds the target group drains a deregistered target (0-3600), defaults to 300
      deregistration_delay = optional(number, null)
      # Hub only: preserve the client address at the target, defaults to false. Targets across a transit gateway
      # reply to that address directly, bypassing the load balancer, so leave it off unless the return path is known
      preserve_client_ip = optional(bool, null)
      # Hub only: send a proxy protocol v2 header to the targets, defaults to false; the targets must expect it
      proxy_protocol_v2 = optional(bool, null)
      # The network interface id (network-interface endpoints)
      network_interface_id = optional(string, null)
      # The CIDR block (cidr endpoints)
      cidr = optional(string, null)
      # The RDS target (rds endpoints); set exactly one of the arns
      rds = optional(object({
        ## The RDS instance ARN
        instance_arn = optional(string, null)
        ## The Aurora cluster ARN
        cluster_arn = optional(string, null)
        ## The RDS Proxy ARN
        proxy_arn = optional(string, null)
        ## The database endpoint address users connect to
        endpoint = string
      }), null)
      # The public DNS name users browse to (http/https endpoints only)
      application_domain = optional(string, null)
      # The public ACM certificate for the application domain (http/https endpoints only)
      domain_certificate_arn = optional(string, null)
      # The prefix for the generated endpoint domain, defaults to the endpoint name
      endpoint_domain_prefix = optional(string, null)
      # Override the subnets for this endpoint, defaults to var.subnet_ids
      subnet_ids = optional(list(string), null)
      # Additional security groups to attach to the endpoint; with create_security_group false, the only ones
      security_group_ids = optional(list(string), [])
      # Create the endpoint security group (<name_prefix>-<name>-<endpoint>, egress only to the targets); false uses
      # only security_group_ids, whose rules must then allow the endpoint to reach its targets
      create_security_group = optional(bool, true)
      # Override the CIDR blocks the endpoint security group may send to
      egress_cidr_blocks = optional(list(string), null)
      # A structured endpoint policy, evaluated in addition to the group policy (both must allow): identity groups
      # narrowing the group's audience and additional Cedar conditions, all combined with AND (and with the device
      # condition when sensitive). The owner and justification default to the group's
      policy = optional(object({
        ## The identity groups permitted to this endpoint (any of); empty leaves the group policy's audience
        identity_groups = optional(list(string), [])
        ## Extra Cedar conditions, each one line, all of which must hold
        additional_conditions = optional(list(string), [])
        ## The team accountable for this access, defaults to the group policy owner
        owner = optional(string, null)
        ## Why this access exists, defaults to the group policy justification
        justification = optional(string, null)
      }), null)
      # Escape hatch: a raw Cedar endpoint policy; requires security review
      raw_policy = optional(object({
        ## The Cedar policy text
        cedar = string
        ## The team accountable for this access
        owner = string
        ## Why the structured policy cannot express this access
        justification = string
      }), null)
      # Tags merged over var.tags and the group tags on the endpoint, its security group, target group and listener
      tags = optional(map(string), {})
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
    condition = try(coalesce(try(var.user_trust_provider.type, null), try(var.existing_instance.user_trust_provider_type, null)), null) != "iam-identity-center" ? true : alltrue([
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
        endpoint.type == "load-balancer" ? endpoint.load_balancer_arn != null || length(endpoint.targets) + length(endpoint.target_details) > 0 :
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
    condition = var.device_trust_provider != null || try(var.existing_instance.device_trust_provider != null, false) ? true : !anytrue([
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
      for target in flatten([for group in values(var.groups) : [for endpoint in values(group.endpoints) : concat(endpoint.targets, endpoint.target_details[*].ip)]]) :
      can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$", target))
    ])
    error_message = "Endpoint targets must be IPv4 addresses, e.g. 10.50.0.10."
  }

  # V25: targets are reached through the central load balancer, which only exists with topology hub
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      length(endpoint.targets) + length(endpoint.target_details) == 0 || (var.topology == "hub" && endpoint.type == "load-balancer")
    ])
    error_message = "Endpoint targets are only supported on load-balancer endpoints with topology hub."
  }

  # V26: a load-balancer endpoint uses either its own load balancer or the central one, not both
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      endpoint.load_balancer_arn == null || length(endpoint.targets) + length(endpoint.target_details) == 0
    ])
    error_message = "A load-balancer endpoint must set either load_balancer_arn or targets, not both."
  }

  # V27: a tcp endpoint with targets maps to exactly one listener port
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      length(endpoint.targets) + length(endpoint.target_details) == 0 || endpoint.protocol != "tcp" || (length(endpoint.port_ranges) == 1 && try(endpoint.port_ranges[0].from_port == endpoint.port_ranges[0].to_port, false))
    ])
    error_message = "A tcp endpoint with targets must have exactly one port range with from_port equal to to_port, which becomes its listener port."
  }

  # V28: each endpoint with targets has its own listener port on the central load balancer: listener_port, or the
  # endpoint port when unset
  validation {
    condition = length([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint if length(endpoint.targets) + length(endpoint.target_details) > 0
      ]) == length(distinct([
        for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
        endpoint.listener_port != null ? endpoint.listener_port : (endpoint.protocol == "tcp" ? try(endpoint.port_ranges[0].from_port, 0) : endpoint.port)
        if length(endpoint.targets) + length(endpoint.target_details) > 0
    ]))
    error_message = "Endpoints with targets must use different listener ports, as each has its own listener on the central load balancer; set listener_port to put several services on the same port."
  }

  # V29: nlb is reserved for the load balancer security group (verified-access-<name>-nlb)
  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : [
        for name, endpoint in group.endpoints : name != "nlb" if length(endpoint.targets) + length(endpoint.target_details) > 0
      ]
    ]))
    error_message = "Endpoints with targets must be named other than nlb, which is reserved for the load balancer security group."
  }

  # V30: endpoints with targets use the module subnets, which the central load balancer accepts traffic from
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      length(endpoint.targets) + length(endpoint.target_details) == 0 || endpoint.subnet_ids == null
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

  # V46: an endpoint has at most one of a structured and a raw policy
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.policy == null || endpoint.raw_policy == null
    ])
    error_message = "An endpoint must set at most one of policy and raw_policy."
  }

  # V47: a structured endpoint policy references a trust provider (identity groups, the device condition of a
  # sensitive endpoint, or an additional condition on the user or device context), as Cedar lint rule L2 requires
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.policy == null ? true : (
        length(endpoint.policy.identity_groups) > 0 || endpoint.sensitive || anytrue([
          for condition in endpoint.policy.additional_conditions : strcontains(condition, format("context.%s.", try(coalesce(try(var.user_trust_provider.policy_reference_name, null), try(var.existing_instance.user_policy_reference_name, null)), ""))) || (
            try(coalesce(try(var.device_trust_provider.policy_reference_name, null), try(var.device_trust_provider.type, null), try(var.existing_instance.device_trust_provider.policy_reference_name, null), try(var.existing_instance.device_trust_provider.type, null)), null) == null ? false : strcontains(condition, format("context.%s.", coalesce(try(var.device_trust_provider.policy_reference_name, null), try(var.device_trust_provider.type, null), try(var.existing_instance.device_trust_provider.policy_reference_name, null), try(var.existing_instance.device_trust_provider.type, null))))
          )
        ])
      )
    ])
    error_message = "An endpoint policy must reference a trust provider: list identity_groups, mark the endpoint sensitive, or add a condition on the user or device context (e.g. context.idc.user.email.address like \"*@example.com\")."
  }

  # V48 (Identity Center): endpoint policy identity groups are group ids, not display names
  validation {
    condition = try(coalesce(try(var.user_trust_provider.type, null), try(var.existing_instance.user_trust_provider_type, null)), null) != "iam-identity-center" ? true : alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.policy == null ? true : alltrue([
        for id in endpoint.policy.identity_groups : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
      ])
    ])
    error_message = "With IAM Identity Center, endpoint policy identity_groups must be group ids (e.g. 11111111-1111-1111-1111-111111111111), not display names."
  }

  # V49: an endpoint policy owner and justification are set together, like any policy's (V12)
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.policy == null ? true : (
        (endpoint.policy.owner == null) == (endpoint.policy.justification == null) && (endpoint.policy.owner == null ? true : (
          length(trimspace(endpoint.policy.owner)) > 0 &&
          length(trimspace(endpoint.policy.justification)) >= 10 &&
          !strcontains(endpoint.policy.owner, "\n") &&
          !strcontains(endpoint.policy.justification, "\n")
        ))
      )
    ])
    error_message = "An endpoint policy sets both or neither of owner and justification (the group's are used when neither is set), with a non-empty owner and a single-line justification of at least 10 characters."
  }

  # V50: additional conditions are single Cedar expressions; a semicolon or line break could end the permit and
  # start another statement
  validation {
    condition = alltrue(flatten([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.policy == null ? [] : [
        for condition in endpoint.policy.additional_conditions : length(trimspace(condition)) > 0 && !strcontains(condition, ";") && !strcontains(condition, "\n")
      ]
    ]))
    error_message = "Each endpoint policy additional_conditions entry must be a single-line Cedar expression without semicolons, e.g. context.http_request.http_method == \"GET\"."
  }

  # V53: detailed targets are IPv4 addresses with valid ports and availability zones, and replace targets
  validation {
    condition = alltrue(flatten([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : concat(
        [length(endpoint.targets) == 0 || length(endpoint.target_details) == 0],
        [
          for target in endpoint.target_details : (
            (target.port == null ? true : target.port >= 1 && target.port <= 65535) &&
            (target.availability_zone == "all" || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9][a-z]$", target.availability_zone)))
          )
        ],
      )
    ]))
    error_message = "Set at most one of targets and target_details; each target_details entry needs a port of 1-65535 (when set) and availability_zone \"all\" or a zone name, e.g. eu-west-2a."
  }

  # V54: each target address and port is registered once per endpoint
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      length(endpoint.target_details) == length(distinct([for target in endpoint.target_details : format("%s:%s", target.ip, target.port == null ? "endpoint" : tostring(target.port))])) &&
      length(endpoint.targets) == length(distinct(endpoint.targets))
    ])
    error_message = "Each target address and port may only be listed once per endpoint."
  }

  # V55: the central load balancer settings apply only to endpoints with targets, and the listener port is valid
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : (
        length(endpoint.targets) + length(endpoint.target_details) > 0 ? true : (
          endpoint.listener_port == null && endpoint.health_check == null && endpoint.deregistration_delay == null &&
          endpoint.preserve_client_ip == null && endpoint.proxy_protocol_v2 == null
        )
        ) && (
        endpoint.listener_port == null ? true : endpoint.listener_port >= 1 && endpoint.listener_port <= 65535
      )
    ])
    error_message = "listener_port, health_check, deregistration_delay, preserve_client_ip and proxy_protocol_v2 only apply to endpoints with targets (topology hub), and listener_port must be 1-65535."
  }

  # V56: the health check is one a network load balancer accepts
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint.health_check == null ? true : (
        contains(["TCP", "HTTP", "HTTPS"], endpoint.health_check.protocol) &&
        (endpoint.health_check.port == "traffic-port" || can(regex("^[0-9]{1,5}$", endpoint.health_check.port)) && try(tonumber(endpoint.health_check.port) >= 1 && tonumber(endpoint.health_check.port) <= 65535, false)) &&
        (endpoint.health_check.protocol == "TCP" ? endpoint.health_check.path == null : endpoint.health_check.path == null || startswith(coalesce(endpoint.health_check.path, "/"), "/")) &&
        endpoint.health_check.healthy_threshold >= 2 && endpoint.health_check.healthy_threshold <= 10 &&
        endpoint.health_check.unhealthy_threshold >= 2 && endpoint.health_check.unhealthy_threshold <= 10 &&
        endpoint.health_check.interval >= 5 && endpoint.health_check.interval <= 300
      )
    ])
    error_message = "A health_check needs protocol TCP, HTTP or HTTPS, port traffic-port or 1-65535, a path starting with / (HTTP and HTTPS only), thresholds of 2-10 and an interval of 5-300 seconds."
  }

  # V57: the deregistration delay is one target groups accept
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      endpoint.deregistration_delay == null ? true : endpoint.deregistration_delay >= 0 && endpoint.deregistration_delay <= 3600
    ])
    error_message = "The deregistration_delay must be between 0 and 3600 seconds."
  }

  # V58: a network load balancer has at most 50 listeners, one per endpoint with targets
  validation {
    condition = length([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) : endpoint if length(endpoint.targets) + length(endpoint.target_details) > 0
    ]) <= 50
    error_message = "At most 50 endpoints may have targets, as each is a listener on the central load balancer (50 listeners per network load balancer). Deploy a second instance of the module for more."
  }

  # V71: an endpoint without the module security group has security groups of its own, and egress_cidr_blocks (a rule
  # of the module security group) is not set
  validation {
    condition = alltrue([
      for endpoint in flatten([for group in values(var.groups) : values(group.endpoints)]) :
      endpoint.create_security_group ? true : length(endpoint.security_group_ids) > 0 && endpoint.egress_cidr_blocks == null
    ])
    error_message = "An endpoint with create_security_group = false needs at least one security_group_ids entry, and cannot set egress_cidr_blocks, which only applies to the security group the module creates."
  }

  # V71: security group ids are well formed
  validation {
    condition = alltrue([
      for id in flatten([for group in values(var.groups) : [for endpoint in values(group.endpoints) : endpoint.security_group_ids]]) : can(regex("^sg-[0-9a-f]+$", id))
    ])
    error_message = "Endpoint security_group_ids must be security group ids, e.g. sg-0123456789abcdef0."
  }
}

variable "kms_key_arn" {
  description = "An optional customer managed KMS key used to encrypt Verified Access trust providers, groups and endpoints; its key policy must permit kms:CreateGrant, DescribeKey, GenerateDataKey and Decrypt via verified-access.<region>.amazonaws.com"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "The kms_key_arn must be a KMS key ARN."
  }

  # V70: the key is either created or supplied
  validation {
    condition     = !(var.create_kms_key && var.kms_key_arn != null)
    error_message = "Set at most one of create_kms_key and kms_key_arn."
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
    ## Balance across the targets in every availability zone; IP targets across a transit gateway have no zone of
    ## their own (availability zone all), so leave it on unless the targets are zonal
    cross_zone_enabled = optional(bool, true)
    ## The rules per security group quota of the account (default 60, inbound and outbound counted separately, one
    ## rule per address range); raise it here after raising the quota (Service Quotas, Amazon VPC)
    max_security_group_rules = optional(number, 60)
    ## Create the load balancer security group (<name_prefix>-<name>-nlb, in from the module subnets on the listener
    ## ports, out to each target); false uses only security_group_ids, whose rules must then allow the endpoint
    ## subnets in on the listener ports and the targets out on their target and health check ports
    create_security_group = optional(bool, true)
    ## Security groups attached to the load balancer: in addition to the created one, or instead of it with
    ## create_security_group false
    security_group_ids = optional(list(string), [])
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

  # V64: the security group rule quota is within the range Amazon VPC allows
  validation {
    condition     = var.load_balancer.max_security_group_rules >= 1 && var.load_balancer.max_security_group_rules <= 1000
    error_message = "The load_balancer.max_security_group_rules must be between 1 and 1000."
  }

  # V72: without the module security group the load balancer has security groups of its own (a network load balancer
  # created with security groups must keep at least one), and the ids are well formed
  validation {
    condition = (
      (var.load_balancer.create_security_group || length(var.load_balancer.security_group_ids) > 0) &&
      alltrue([for id in var.load_balancer.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    )
    error_message = "With load_balancer.create_security_group = false, set at least one load_balancer.security_group_ids entry; each must be a security group id, e.g. sg-0123456789abcdef0."
  }
}

variable "metric_stream" {
  description = "An optional CloudWatch metric stream to a Kinesis Data Firehose delivery stream, e.g. for an external observability platform: by default the log derived metrics and, with topology hub, the AWS/NetworkELB namespace, or only the metrics chosen in include; null disables it"
  type = object({
    ## The ARN of the Kinesis Data Firehose delivery stream receiving the metrics
    firehose_arn = string
    ## The ARN of an existing IAM role CloudWatch assumes to write to the delivery stream
    role_arn = optional(string, null)
    ## Instead of role_arn: create the role (<name_prefix>-<name>-metric-stream), trusted by CloudWatch metric streams
    ## in this account and permitted to write only to firehose_arn
    create_role = optional(bool, false)
    ## The output format (json, opentelemetry0.7, opentelemetry1.0)
    output_format = optional(string, "opentelemetry1.0")
    ## The metrics to stream, by key of the metrics output, e.g. ["access-denied", "<endpoint>/healthy-host-count"];
    ## null streams every log derived metric and, with topology hub, the whole AWS/NetworkELB namespace. A stream
    ## filters by namespace and metric name, not dimension, so an AWS/NetworkELB or AWS/Logs metric is streamed for
    ## every load balancer or log group in the account and region
    include = optional(list(string), null)
  })
  default = null

  # V41: the stream carries metrics: by default the log derived metrics (at least one metric filter), or the chosen
  # ones; an empty include filter would stream every metric in the account
  validation {
    condition = var.metric_stream == null ? true : (
      var.metric_stream.include != null ? length(var.metric_stream.include) > 0 : try(
        var.access_logs.cloudwatch.metric_filters == null ? true : length(var.access_logs.cloudwatch.metric_filters) > 0, false
      )
    )
    error_message = "The metric stream needs metrics to stream: access_logs.cloudwatch with at least one metric filter (Verified Access publishes no metrics of its own), or a non-empty metric_stream.include."
  }

  # V42: the delivery stream, role and output format are well formed
  validation {
    condition = var.metric_stream == null ? true : (
      can(regex("^arn:aws[a-z-]*:firehose:", var.metric_stream.firehose_arn)) &&
      (var.metric_stream.role_arn == null ? true : can(regex("^arn:aws[a-z-]*:iam::", var.metric_stream.role_arn))) &&
      contains(["json", "opentelemetry0.7", "opentelemetry1.0"], var.metric_stream.output_format)
    )
    error_message = "The metric_stream needs a Firehose delivery stream ARN, an IAM role ARN and an output_format of json, opentelemetry0.7 or opentelemetry1.0."
  }

  # V73: the role is either created or supplied
  validation {
    condition     = var.metric_stream == null ? true : (var.metric_stream.role_arn != null) != var.metric_stream.create_role
    error_message = "The metric_stream must set exactly one of role_arn or create_role = true."
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

variable "name_prefix" {
  description = "The prefix of all resource names, to follow the caller's naming convention, e.g. prod-euw2-va gives prod-euw2-va-<name>-nlb; scope pipeline roles to <name_prefix>-*"
  type        = string
  default     = "verified-access"

  # V45: the prefix is safe in every resource name, and leaves room for a target group hash of at least 8 characters
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,21}[a-z0-9])?$", var.name_prefix))
    error_message = "The name_prefix must be lowercase alphanumeric and hyphens, starting and ending with an alphanumeric character (max 23)."
  }
}

variable "oidc_client_secret" {
  description = "The OAuth client secret for an OIDC user trust provider; source it from a secret store, never from tfvars"
  type        = string
  default     = null
  sensitive   = true

  # V4: an OIDC provider needs a client secret
  validation {
    condition     = try(var.user_trust_provider.type, null) != "oidc" ? true : var.oidc_client_secret != null
    error_message = "The oidc_client_secret is required when user_trust_provider.type is oidc."
  }
}

variable "oidc_native_client_secret" {
  description = "The OAuth client secret of a separate native application client (user_trust_provider.oidc.native_client_id), defaults to oidc_client_secret; source it from a secret store, never from tfvars"
  type        = string
  default     = null
  sensitive   = true

  # V52: the secret belongs to a native application client, and a separate client has its own secret
  validation {
    condition = (
      var.oidc_native_client_secret == null ? true : try(var.user_trust_provider.oidc.public_signing_key_endpoint != null, false)
      ) && (
      try(var.user_trust_provider.oidc.native_client_id == null || var.user_trust_provider.oidc.native_client_id == var.user_trust_provider.oidc.client_id, true) || var.oidc_native_client_secret != null
    )
    error_message = "The oidc_native_client_secret requires an OIDC provider with public_signing_key_endpoint, and is required when native_client_id differs from client_id."
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

  # V23: the load balancer name <name_prefix>-<name> fits in 32 characters
  validation {
    condition     = var.topology != "hub" || length(var.name_prefix) + length(var.name) <= 31
    error_message = "With topology hub the name_prefix plus the name must be at most 31 characters, as the load balancer is named <name_prefix>-<name> (max 32)."
  }
}

variable "user_trust_provider" {
  description = "The user identity trust provider the module creates, IAM Identity Center or an OIDC identity provider; required unless existing_instance is set, which describes the provider already attached instead"
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
      # The claim holding the user's groups, rendered into the policies as context.<policy_reference_name>.<claim>;
      # a dotted path reaches a nested claim, e.g. additional_user_context.groups
      groups_claim = optional(string, "groups")
      # A separate OAuth client for the native application (Connectivity Client), defaults to client_id; its secret
      # is passed in oidc_native_client_secret
      native_client_id = optional(string, null)
      # The scopes of the native application client, defaults to scope
      native_scope = optional(string, null)
    }), null)
  })
  default = null

  # V2: the user provider type is supported by Verified Access
  validation {
    condition     = var.user_trust_provider == null ? true : contains(["iam-identity-center", "oidc"], var.user_trust_provider.type)
    error_message = "The user_trust_provider.type must be iam-identity-center or oidc."
  }

  # V3: the policy reference name is a valid Cedar identifier
  validation {
    condition     = var.user_trust_provider == null ? true : can(regex("^[a-z][a-z0-9_]{0,31}$", var.user_trust_provider.policy_reference_name))
    error_message = "The user_trust_provider.policy_reference_name must start with a lowercase letter and contain only lowercase letters, digits and underscores (max 32)."
  }

  # V4: the OIDC settings are present exactly when the type is oidc
  validation {
    condition     = var.user_trust_provider == null ? true : (var.user_trust_provider.type == "oidc") == (var.user_trust_provider.oidc != null)
    error_message = "Set user_trust_provider.oidc when type is oidc, and only then."
  }

  # V51: the groups claim is a Cedar attribute path
  validation {
    condition     = try(var.user_trust_provider.oidc, null) == null ? true : can(regex("^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$", var.user_trust_provider.oidc.groups_claim))
    error_message = "The user_trust_provider.oidc.groups_claim must be a claim name or dotted path of letters, digits and underscores, e.g. groups or additional_user_context.groups; use raw_policy for claims such as URLs."
  }

  # V52: a native application client needs the public signing key endpoint that enables native application access
  validation {
    condition = try(var.user_trust_provider.oidc, null) == null ? true : (
      var.user_trust_provider.oidc.native_client_id == null && var.user_trust_provider.oidc.native_scope == null
    ) || var.user_trust_provider.oidc.public_signing_key_endpoint != null
    error_message = "The user_trust_provider.oidc.native_client_id and native_scope require public_signing_key_endpoint, which enables native application (Connectivity Client) access."
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
