locals {
  ## Indicates alarms are configured
  enable_alarms = var.alarms != null
  ## Indicates the module creates the alarm topic
  enable_alarm_topic = local.enable_alarms ? var.alarms.sns_topic_arn == null : false
  ## Indicates changes made outside the deployment pipeline raise an alarm
  enable_change_alarm = local.enable_alarms ? var.alarms.pipeline_role_name != null : false
  ## Indicates the module creates the key encrypting the alarm topic
  enable_alarm_kms_key = local.enable_alarm_topic ? var.alarms.create_kms_key : false
  ## The key encrypting the alarm topic, when encrypted
  alarm_kms_key_arn = local.enable_alarm_kms_key ? aws_kms_key.alarms[0].arn : try(var.alarms.kms_key_arn, null)
  ## The topic notified by the alarms
  alarm_topic_arn = !local.enable_alarms ? null : (
    local.enable_alarm_topic ? aws_sns_topic.alarms[0].arn : var.alarms.sns_topic_arn
  )

  ## The actions notified on alarm and on recovery: the topic and any additional actions
  alarm_actions = !local.enable_alarms ? [] : distinct(concat([local.alarm_topic_arn], var.alarms.additional_action_arns))

  ## The alarms on the log derived metrics; Verified Access publishes no metrics of its own. Each alarm carries its
  ## kind, the key alarms.disabled and alarms.overrides refer to
  access_alarms = !local.enable_alarms ? {} : {
    http-504 = {
      kind                = "http-504"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      description         = "HTTP endpoints are returning 504s: applications are slower than the 60 second Verified Access limit"
      dimensions          = {}
      evaluation_periods  = 1
      metric_name         = "Http504"
      namespace           = local.metric_namespace
      period              = 300
      statistic           = "Sum"
      threshold           = var.alarms.thresholds.http_504
      treat_missing_data  = "notBreaching"
    }
    access-denied = {
      kind                = "access-denied"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      description         = "A spike in denied requests: a policy change has gone wrong, or someone is probing the endpoints"
      dimensions          = {}
      evaluation_periods  = 1
      metric_name         = "AccessDenied"
      namespace           = local.metric_namespace
      period              = 300
      statistic           = "Sum"
      threshold           = var.alarms.thresholds.access_denied
      treat_missing_data  = "notBreaching"
    }
    logging-stopped = {
      kind                = "logging-stopped"
      comparison_operator = "LessThanThreshold"
      description         = "No access logs received: the audit trail is broken, or nobody is using Verified Access"
      dimensions          = { LogGroupName = local.log_group_name }
      evaluation_periods  = var.alarms.thresholds.logging_stopped_hours
      metric_name         = "IncomingLogEvents"
      namespace           = "AWS/Logs"
      period              = 3600
      statistic           = "Sum"
      threshold           = 1
      treat_missing_data  = "breaching"
    }
    no-access-allowed = {
      kind                = "no-access-allowed"
      comparison_operator = "LessThanThreshold"
      description         = "Nobody has been allowed access: a possible outage nobody has reported"
      dimensions          = {}
      evaluation_periods  = var.alarms.thresholds.no_access_allowed_hours
      metric_name         = "AccessAllowed"
      namespace           = local.metric_namespace
      period              = 3600
      statistic           = "Sum"
      threshold           = 1
      treat_missing_data  = "breaching"
    }
  }

  ## The alarms on the central load balancer, per target group: no healthy targets (critical) and unhealthy targets
  load_balancer_alarms = !local.enable_alarms ? {} : merge([
    for name, _ in local.load_balancer_endpoints : {
      format("%s-no-healthy-targets", name) = {
        kind                = "no-healthy-targets"
        comparison_operator = "LessThanThreshold"
        description         = format("No healthy targets behind the central load balancer for %s: the service is unreachable", name)
        dimensions          = { LoadBalancer = aws_lb.current[0].arn_suffix, TargetGroup = aws_lb_target_group.current[name].arn_suffix }
        evaluation_periods  = 2
        metric_name         = "HealthyHostCount"
        namespace           = "AWS/NetworkELB"
        period              = 60
        statistic           = "Minimum"
        threshold           = 1
        treat_missing_data  = "breaching"
      }
      format("%s-unhealthy-targets", name) = {
        kind                = "unhealthy-targets"
        comparison_operator = "GreaterThanThreshold"
        description         = format("Unhealthy targets behind the central load balancer for %s: the service is degraded", name)
        dimensions          = { LoadBalancer = aws_lb.current[0].arn_suffix, TargetGroup = aws_lb_target_group.current[name].arn_suffix }
        evaluation_periods  = 5
        metric_name         = "UnHealthyHostCount"
        namespace           = "AWS/NetworkELB"
        period              = 60
        statistic           = "Maximum"
        threshold           = 0
        treat_missing_data  = "notBreaching"
      }
    }
  ]...)

  ## The alarms created: every alarm not disabled, with its overrides applied
  alarms = !local.enable_alarms ? {} : {
    for name, alarm in merge(local.access_alarms, local.load_balancer_alarms) : name => merge(alarm, {
      evaluation_periods = coalesce(try(var.alarms.overrides[alarm.kind].evaluation_periods, null), alarm.evaluation_periods)
      period             = coalesce(try(var.alarms.overrides[alarm.kind].period, null), alarm.period)
      threshold          = coalesce(try(var.alarms.overrides[alarm.kind].threshold, null), alarm.threshold)
    }) if !contains(var.alarms.disabled, alarm.kind)
  }
}

## Provision the key encrypting the alarm topic, when requested. CloudWatch and EventBridge cannot publish to a topic
## encrypted with the AWS managed SNS key, so the key policy permits both services in this account to use it
resource "aws_kms_key" "alarms" {
  count = local.enable_alarm_kms_key ? 1 : 0

  description         = format("Encrypts the Verified Access %s alarm topic", var.name)
  enable_key_rotation = true
  tags                = merge(local.tags, { Name = format("%s-alarms", local.resource_name) })

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAdministration"
        Effect    = "Allow"
        Action    = "kms:*"
        Resource  = "*"
        Principal = { AWS = format("arn:%s:iam::%s:root", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id) }
      },
      {
        Sid       = "AllowAlarmPublishers"
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Principal = { Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"] }
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

## Name the alarm topic key so it can be found in the console
resource "aws_kms_alias" "alarms" {
  count = local.enable_alarm_kms_key ? 1 : 0

  name          = format("alias/%s-alarms", local.resource_name)
  target_key_id = aws_kms_key.alarms[0].key_id
}

## Provision the topic receiving the alarms, unless an existing topic is supplied. Encryption is optional (a key the
## module creates, or a supplied one) so the module works without one
resource "aws_sns_topic" "alarms" {
  count = local.enable_alarm_topic ? 1 : 0

  kms_master_key_id = local.alarm_kms_key_arn
  name              = format("%s-alarms", local.resource_name)
  tags              = merge(local.tags, { Name = format("%s-alarms", local.resource_name) })
}

## Permit CloudWatch alarms and EventBridge rules in this account to publish to the topic
resource "aws_sns_topic_policy" "alarms" {
  count = local.enable_alarm_topic ? 1 : 0

  arn = aws_sns_topic.alarms[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAlarms"
        Effect    = "Allow"
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alarms[0].arn
        Principal = { Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"] }
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

## Subscribe the alarm recipients to the topic
resource "aws_sns_topic_subscription" "alarms" {
  for_each = local.enable_alarms ? toset(var.alarms.email_addresses) : toset([])

  endpoint  = each.value
  protocol  = "email"
  topic_arn = local.alarm_topic_arn
}

## Provision the alarms on the log derived metrics and the central load balancer
resource "aws_cloudwatch_metric_alarm" "current" {
  for_each = local.alarms

  alarm_actions       = local.alarm_actions
  alarm_description   = each.value.description
  alarm_name          = format("%s-%s", local.resource_name, each.key)
  comparison_operator = each.value.comparison_operator
  dimensions          = each.value.dimensions
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  ok_actions          = local.alarm_actions
  period              = each.value.period
  statistic           = each.value.statistic
  tags                = local.tags
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data
}

## Alarm when Verified Access is changed by anyone other than the pipeline role, protecting the approval gate. IAM
## users and the root user have no session issuer, so they are matched by identity type
resource "aws_cloudwatch_event_rule" "changed_outside_pipeline" {
  count = local.enable_change_alarm ? 1 : 0

  description = "Verified Access was changed by a principal other than the deployment pipeline"
  name        = format("%s-changed-outside-pipeline", local.resource_name)
  tags        = local.tags

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [{ wildcard = "*VerifiedAccess*" }]
      readOnly  = [false]
      "$or" = [
        { userIdentity = { sessionContext = { sessionIssuer = { userName = [{ anything-but = var.alarms.pipeline_role_name }] } } } },
        { userIdentity = { type = ["IAMUser", "Root"] } },
      ]
    }
  })
}

## Send the changes made outside the pipeline to the alarm topic
resource "aws_cloudwatch_event_target" "changed_outside_pipeline" {
  count = local.enable_change_alarm ? 1 : 0

  arn       = local.alarm_topic_arn
  rule      = aws_cloudwatch_event_rule.changed_outside_pipeline[0].name
  target_id = "alarms"
}
