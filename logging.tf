locals {
  ## Indicates access logging is configured
  enable_access_logs = var.access_logs != null
  ## Indicates access logs are delivered to CloudWatch Logs
  enable_cloudwatch_logs = local.enable_access_logs ? var.access_logs.cloudwatch != null : false
  ## Indicates the log derived metric filters and saved queries are created
  enable_metric_filters = local.enable_cloudwatch_logs ? var.access_logs.cloudwatch.enable_metric_filters : false
  ## Indicates the module creates the CloudWatch log group, rather than delivering to an existing one
  enable_log_group = local.enable_cloudwatch_logs ? var.access_logs.cloudwatch.create_log_group : false
  ## The name of the CloudWatch log group for the access logs
  log_group_name = local.enable_cloudwatch_logs ? coalesce(var.access_logs.cloudwatch.log_group_name, format("/aws/%s/%s", var.name_prefix, var.name)) : null
  ## The log group the logs, metric filters and queries use: the created one (so it exists first), or the existing one
  access_log_group = local.enable_log_group ? aws_cloudwatch_log_group.access_logs[0].name : local.log_group_name
  ## The CloudWatch metric namespace for the log derived metrics
  metric_namespace = format("VerifiedAccess/%s", var.name)

  ## Log derived metrics: Verified Access publishes no CloudWatch metrics of its own. HTTP and TCP entries
  ## carry the decision in different places (actor.authorizations vs data.authorizations)
  metric_filters = {
    allowed-http = { metric = "AccessAllowed", pattern = "{ $.actor.authorizations[0].decision = \"Allow\" }" }
    allowed-tcp  = { metric = "AccessAllowed", pattern = "{ $.data.authorizations[0].decision = \"Allow\" }" }
    denied-http  = { metric = "AccessDenied", pattern = "{ $.actor.authorizations[0].decision != \"Allow\" }" }
    denied-tcp   = { metric = "AccessDenied", pattern = "{ $.data.authorizations[0].decision != \"Allow\" }" }
    http-504     = { metric = "Http504", pattern = "{ $.http_response.code = 504 }" }
    http-5xx     = { metric = "Http5xx", pattern = "{ $.http_response.code >= 500 }" }
  }

  ## Saved Logs Insights queries answering "who is connecting now" and "what was denied"
  queries = {
    who-is-connecting = <<-EOT
      fields @timestamp, coalesce(actor.user.email_addr, user.email_addr) as user, coalesce(http_request.url.hostname, privileges.0) as target
      | filter coalesce(actor.authorizations.0.decision, data.authorizations.0.decision) = "Allow"
      | stats count(*) as requests, max(@timestamp) as last_seen by user, target
      | sort last_seen desc
    EOT
    denied-requests   = <<-EOT
      fields @timestamp, coalesce(actor.user.email_addr, user.email_addr) as user, coalesce(http_request.url.hostname, privileges.0) as target, status_detail
      | filter coalesce(actor.authorizations.0.decision, data.authorizations.0.decision) != "Allow"
      | sort @timestamp desc
      | limit 200
    EOT
  }
}

## Provision the CloudWatch log group so retention (personal data) is always bounded, unless an existing one is used
resource "aws_cloudwatch_log_group" "access_logs" {
  count = local.enable_log_group ? 1 : 0

  kms_key_id        = var.access_logs.cloudwatch.kms_key_arn
  name              = local.log_group_name
  retention_in_days = var.access_logs.cloudwatch.retention_in_days
  tags              = local.tags
}

## Configure where the instance delivers its access logs
resource "aws_verifiedaccess_instance_logging_configuration" "current" {
  count = local.enable_access_logs ? 1 : 0

  verifiedaccess_instance_id = aws_verifiedaccess_instance.current.id

  access_logs {
    include_trust_context = var.access_logs.include_trust_context
    log_version           = var.access_logs.log_version

    cloudwatch_logs {
      enabled   = local.enable_cloudwatch_logs
      log_group = local.access_log_group
    }

    kinesis_data_firehose {
      delivery_stream = var.access_logs.firehose_delivery_stream_name
      enabled         = var.access_logs.firehose_delivery_stream_name != null
    }

    s3 {
      bucket_name  = try(var.access_logs.s3.bucket_name, null)
      bucket_owner = try(var.access_logs.s3.bucket_owner, null)
      enabled      = var.access_logs.s3 != null
      prefix       = try(var.access_logs.s3.prefix, null)
    }
  }
}

## Provision the log derived metrics
resource "aws_cloudwatch_log_metric_filter" "access" {
  for_each = local.enable_metric_filters ? local.metric_filters : {}

  log_group_name = local.access_log_group
  name           = format("%s-%s", local.resource_name, each.key)
  pattern        = each.value.pattern

  metric_transformation {
    default_value = 0
    name          = each.value.metric
    namespace     = local.metric_namespace
    unit          = "Count"
    value         = "1"
  }
}

## Provision the saved Logs Insights queries
resource "aws_cloudwatch_query_definition" "access" {
  for_each = local.enable_metric_filters ? local.queries : {}

  log_group_names = [local.access_log_group]
  name            = format("%s/%s/%s", var.name_prefix, var.name, each.key)
  query_string    = each.value
}
