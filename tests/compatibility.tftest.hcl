## Compatibility tests: the input shape of a known hub deployment (two endpoints with targets on the central load
## balancer, one http with its own domain and certificate, access logs to CloudWatch with trust context, email alarms
## with the pipeline role and a dashboard) keeps creating the same alarms, metric filters, queries, dashboard, topic
## and pipeline rule, with the same thresholds, as the interface is refined.
##
## Deliberate changes for this caller, each an in-place update or a replacement that keeps the endpoints:
## - the log derived metrics moved from VerifiedAccess/<name> to VerifiedAccess/<name_prefix>-<name> (metric filters,
##   three alarms and the dashboard updated in place; history stays under the old namespace)
## - target group names hash the VPC and target port too, so both target groups are replaced (created before
##   destroyed), their target registrations replaced, and the listeners and load balancer alarms updated in place
## - the instance, trust provider, group and endpoint Name tags became <name_prefix>-<name>[-...] (tags only)

mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-west-2:111111111111:verified-access-hub-alarms"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/verified-access-hub/0123456789abcdef"
      arn_suffix = "net/verified-access-hub/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/verified-access/0123456789abcdef"
      arn_suffix = "targetgroup/verified-access/0123456789abcdef"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  override_data {
    target = data.aws_subnet.load_balancer[0]
    values = { cidr_block = "10.10.0.0/24" }
  }
}

variables {
  name        = "hub"
  description = "Verified Access for the hub"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0"]
  topology    = "hub"

  tags = {
    "Environment" = "Testing"
    "GitRepo"     = "https://github.com/appvia/terraform-aws-verified-access"
  }

  user_trust_provider = {
    type                   = "iam-identity-center"
    require_verified_email = false
  }

  access_logs = {
    include_trust_context = true
    cloudwatch = {
      retention_in_days = 365
    }
  }

  alarms = {
    email_addresses    = ["platform@example.com"]
    pipeline_role_name = "pipeline"
  }

  dashboard = {}

  groups = {
    platform-engineers = {
      description = "Platform engineers"
      policy = {
        identity_groups = ["11111111-1111-1111-1111-111111111111"]
        owner           = "platform-team"
        justification   = "Platform engineers operate the tenant services"
      }
      endpoints = {
        app-ssh = {
          type        = "load-balancer"
          port_ranges = [{ from_port = 22, to_port = 22 }]
          targets     = ["10.50.0.10"]
        }
        app-web = {
          type                   = "load-balancer"
          protocol               = "http"
          port                   = 80
          targets                = ["10.50.0.20"]
          application_domain     = "app.example.com"
          domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/00000000-0000-0000-0000-000000000000"
        }
      }
    }
  }
}

run "same_monitoring_resources" {
  command = apply

  assert {
    condition = toset(keys(aws_cloudwatch_metric_alarm.current)) == toset([
      "http-504", "access-denied", "logging-stopped", "no-access-allowed",
      "app-ssh-no-healthy-targets", "app-ssh-unhealthy-targets",
      "app-web-no-healthy-targets", "app-web-unhealthy-targets",
    ])
    error_message = "The same alarms should be created, keyed as before"
  }

  assert {
    condition = {
      for key, alarm in aws_cloudwatch_metric_alarm.current : key => [
        alarm.namespace, alarm.metric_name, alarm.statistic, alarm.comparison_operator, alarm.threshold, alarm.period,
        alarm.evaluation_periods, alarm.treat_missing_data, alarm.alarm_name,
      ]
      } == {
      "http-504"                   = ["VerifiedAccess/verified-access-hub", "Http504", "Sum", "GreaterThanOrEqualToThreshold", 5, 300, 1, "notBreaching", "verified-access-hub-http-504"]
      "access-denied"              = ["VerifiedAccess/verified-access-hub", "AccessDenied", "Sum", "GreaterThanOrEqualToThreshold", 20, 300, 1, "notBreaching", "verified-access-hub-access-denied"]
      "logging-stopped"            = ["AWS/Logs", "IncomingLogEvents", "Sum", "LessThanThreshold", 1, 3600, 1, "breaching", "verified-access-hub-logging-stopped"]
      "no-access-allowed"          = ["VerifiedAccess/verified-access-hub", "AccessAllowed", "Sum", "LessThanThreshold", 1, 3600, 24, "breaching", "verified-access-hub-no-access-allowed"]
      "app-ssh-no-healthy-targets" = ["AWS/NetworkELB", "HealthyHostCount", "Minimum", "LessThanThreshold", 1, 60, 2, "breaching", "verified-access-hub-app-ssh-no-healthy-targets"]
      "app-ssh-unhealthy-targets"  = ["AWS/NetworkELB", "UnHealthyHostCount", "Maximum", "GreaterThanThreshold", 0, 60, 5, "notBreaching", "verified-access-hub-app-ssh-unhealthy-targets"]
      "app-web-no-healthy-targets" = ["AWS/NetworkELB", "HealthyHostCount", "Minimum", "LessThanThreshold", 1, 60, 2, "breaching", "verified-access-hub-app-web-no-healthy-targets"]
      "app-web-unhealthy-targets"  = ["AWS/NetworkELB", "UnHealthyHostCount", "Maximum", "GreaterThanThreshold", 0, 60, 5, "notBreaching", "verified-access-hub-app-web-unhealthy-targets"]
    }
    error_message = "Each alarm should keep its metric, statistic, threshold, period, evaluation periods and name"
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_metric_filter.access)) == toset(["allowed-http", "allowed-tcp", "denied-http", "denied-tcp", "http-504", "http-5xx"])
    error_message = "The same metric filters should be created, keyed as before"
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_query_definition.access)) == toset(["who-is-connecting", "denied-requests"])
    error_message = "The same saved queries should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.access_logs) == 1 && aws_cloudwatch_log_group.access_logs[0].retention_in_days == 365
    error_message = "The log group should still be created with the requested retention"
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.current) == 1 && aws_cloudwatch_dashboard.current[0].dashboard_name == "verified-access-hub"
    error_message = "The dashboard should still be created"
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.current[0].dashboard_body).widgets) == 4
    error_message = "The dashboard should keep its four widgets"
  }

  assert {
    condition = alltrue([
      aws_lb_target_group.current["app-ssh"].name == format("verified-access-%s", substr(sha1("hub/app-ssh/vpc-0123456789abcdef0/22"), 0, 16)),
      aws_lb_target_group.current["app-web"].name == format("verified-access-%s", substr(sha1("hub/app-web/vpc-0123456789abcdef0/80"), 0, 16)),
      aws_lb_listener.current["app-ssh"].port == 22,
      aws_lb_listener.current["app-web"].port == 80,
    ])
    error_message = "The target groups should be named by the hash of name/endpoint/VPC/target port, behind the same listeners"
  }

  assert {
    condition = alltrue([
      aws_verifiedaccess_instance.current[0].tags["Name"] == "verified-access-hub",
      aws_verifiedaccess_trust_provider.user[0].tags["Name"] == "verified-access-hub-user",
    ])
    error_message = "The instance and trust provider should be tagged <name_prefix>-<name>"
  }

  assert {
    condition     = length(data.aws_vpc.current) == 0 && length(data.aws_route53_zone.current) == 0
    error_message = "Endpoints with targets send only to the module subnets, so the VPC is not read; without dns no zone is read"
  }

  assert {
    condition     = length(aws_sns_topic.alarms) == 1 && length(aws_sns_topic_policy.alarms) == 1 && length(aws_kms_key.alarms) == 0
    error_message = "The module should still create the unencrypted alarm topic"
  }

  assert {
    condition     = toset(keys(aws_sns_topic_subscription.alarms)) == toset(["platform@example.com"])
    error_message = "The email recipient should still be subscribed"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.changed_outside_pipeline) == 1 && length(aws_cloudwatch_event_target.changed_outside_pipeline) == 1
    error_message = "The changed outside the pipeline rule should still be created"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.custom) == 0
    error_message = "No custom alarms should be created"
  }

  assert {
    condition = toset([for key, metric in output.metrics : key if metric.source == "log metric filter"]) == toset([
      "access-allowed", "access-denied", "http-504", "http-5xx",
    ]) && output.metric_namespace == "VerifiedAccess/verified-access-hub"
    error_message = "All four log derived metrics should be available in the same namespace"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.access_logs) == 0 && length(aws_s3_bucket.access_logs) == 0 && length(aws_cloudwatch_metric_stream.current) == 0
    error_message = "No Firehose stream, bucket or metric stream should be created"
  }

  assert {
    condition = alltrue([
      aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].include_trust_context,
      aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].cloudwatch_logs[0].enabled,
      !aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].kinesis_data_firehose[0].enabled,
      !aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].s3[0].enabled,
    ])
    error_message = "The logging configuration should still deliver to CloudWatch Logs only, with trust context"
  }
}
