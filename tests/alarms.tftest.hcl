## Alarm tests: the topic and its policy, the alarms on the log derived metrics and the central load balancer, and the
## alarm on changes made outside the pipeline.

mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-west-2:111111111111:verified-access-test-alarms"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/verified-access-test/0123456789abcdef"
      arn_suffix = "net/verified-access-test/0123456789abcdef"
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
  name       = "test"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0"]

  tags = {
    "Environment" = "Testing"
    "GitRepo"     = "https://github.com/appvia/terraform-aws-verified-access"
  }

  user_trust_provider = {
    type = "iam-identity-center"
  }

  access_logs = {
    cloudwatch = {}
  }

  alarms = {}

  groups = {}
}

run "default_alarms" {
  command = apply

  assert {
    condition     = aws_sns_topic.alarms[0].name == "verified-access-test-alarms"
    error_message = "The module should create the alarm topic verified-access-<name>-alarms"
  }

  assert {
    condition     = aws_sns_topic.alarms[0].kms_master_key_id == null
    error_message = "The topic should not be encrypted with a key unless one is supplied"
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
    error_message = "The topic policy should be scoped to this account"
  }

  assert {
    condition = alltrue([
      for service in ["cloudwatch.amazonaws.com", "events.amazonaws.com"] : contains(jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[0].Principal.Service, service)
    ])
    error_message = "The topic policy should permit CloudWatch and EventBridge to publish"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.current) == 4
    error_message = "The four log derived alarms should be created"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.current["http-504"].alarm_name == "verified-access-test-http-504" && aws_cloudwatch_metric_alarm.current["http-504"].threshold == 5
    error_message = "The HTTP 504 alarm should default to 5 in five minutes"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.current["access-denied"].threshold == 20 && aws_cloudwatch_metric_alarm.current["access-denied"].namespace == "VerifiedAccess/test"
    error_message = "The denial alarm should default to 20 on the log derived metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.current["logging-stopped"].dimensions["LogGroupName"] == "/aws/verified-access/test" && aws_cloudwatch_metric_alarm.current["logging-stopped"].evaluation_periods == 1
    error_message = "The logging stopped alarm should watch the access log group for an hour"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.current["no-access-allowed"].evaluation_periods == 24 && aws_cloudwatch_metric_alarm.current["no-access-allowed"].treat_missing_data == "breaching"
    error_message = "The no access allowed alarm should default to 24 hours, with missing data breaching"
  }

  assert {
    condition     = alltrue([for alarm in aws_cloudwatch_metric_alarm.current : contains(alarm.alarm_actions, aws_sns_topic.alarms[0].arn) && contains(alarm.ok_actions, aws_sns_topic.alarms[0].arn)])
    error_message = "Every alarm should notify the topic"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.changed_outside_pipeline) == 0 && length(aws_sns_topic_subscription.alarms) == 0
    error_message = "No change alarm or subscriptions should be created unless configured"
  }

  assert {
    condition     = output.alarm_topic_arn == aws_sns_topic.alarms[0].arn
    error_message = "The alarm topic should be exported"
  }
}

run "configured_alarms" {
  command = apply

  variables {
    alarms = {
      kms_key_arn        = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
      email_addresses    = ["platform@example.com", "security@example.com"]
      pipeline_role_name = "verified-access-pipeline"
      rules = {
        http-504          = { threshold = 10 }
        access-denied     = { threshold = 50 }
        logging-stopped   = { evaluation_periods = 6 }
        no-access-allowed = { evaluation_periods = 72 }
      }
    }
  }

  assert {
    condition     = aws_sns_topic.alarms[0].kms_master_key_id == "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The topic should be encrypted with the supplied key"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.alarms) == 2 && aws_sns_topic_subscription.alarms["platform@example.com"].protocol == "email"
    error_message = "Each recipient should be subscribed by email"
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.current["http-504"].threshold == 10,
      aws_cloudwatch_metric_alarm.current["access-denied"].threshold == 50,
      aws_cloudwatch_metric_alarm.current["logging-stopped"].evaluation_periods == 6,
      aws_cloudwatch_metric_alarm.current["no-access-allowed"].evaluation_periods == 72,
    ])
    error_message = "The thresholds and alarm windows should be configurable per alarm"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.changed_outside_pipeline[0].name == "verified-access-test-changed-outside-pipeline"
    error_message = "The change alarm should be named verified-access-<name>-changed-outside-pipeline"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.changed_outside_pipeline[0].event_pattern).detail["$or"][0].userIdentity.sessionContext.sessionIssuer.userName[0]["anything-but"] == "verified-access-pipeline"
    error_message = "The change alarm should ignore the pipeline role"
  }

  assert {
    condition     = contains(jsondecode(aws_cloudwatch_event_rule.changed_outside_pipeline[0].event_pattern).detail["$or"][1].userIdentity.type, "IAMUser")
    error_message = "The change alarm should match IAM users, which have no session issuer"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.changed_outside_pipeline[0].event_pattern).detail.eventName[0].wildcard == "*VerifiedAccess*"
    error_message = "The change alarm should match Verified Access API calls"
  }

  assert {
    condition     = aws_cloudwatch_event_target.changed_outside_pipeline[0].arn == aws_sns_topic.alarms[0].arn
    error_message = "The change alarm should notify the topic"
  }
}

run "created_alarm_key" {
  command = apply

  variables {
    alarms = {
      create_kms_key = true
    }
  }

  assert {
    condition     = length(aws_kms_key.alarms) == 1 && aws_kms_key.alarms[0].enable_key_rotation == true
    error_message = "The module should create a rotating key for the topic"
  }

  assert {
    condition     = aws_kms_alias.alarms[0].name == "alias/verified-access-test-alarms"
    error_message = "The key should be aliased alias/verified-access-<name>-alarms"
  }

  assert {
    condition     = aws_sns_topic.alarms[0].kms_master_key_id == aws_kms_key.alarms[0].arn && output.alarm_kms_key_arn == aws_kms_key.alarms[0].arn
    error_message = "The topic should be encrypted with the created key, and the key exported"
  }

  assert {
    condition     = contains(jsondecode(aws_kms_key.alarms[0].policy).Statement[1].Principal.Service, "cloudwatch.amazonaws.com") && contains(jsondecode(aws_kms_key.alarms[0].policy).Statement[1].Principal.Service, "events.amazonaws.com")
    error_message = "The key policy should permit CloudWatch and EventBridge to publish"
  }
}

run "existing_topic" {
  command = plan

  variables {
    alarms = {
      create_sns_topic = false
      sns_topic_arn    = "arn:aws:sns:eu-west-2:111111111111:existing"
    }
  }

  assert {
    condition     = length(aws_sns_topic.alarms) == 0 && length(aws_sns_topic_policy.alarms) == 0
    error_message = "No topic should be created when one is supplied"
  }

  assert {
    condition     = alltrue([for alarm in aws_cloudwatch_metric_alarm.current : contains(alarm.alarm_actions, "arn:aws:sns:eu-west-2:111111111111:existing")])
    error_message = "The alarms should notify the supplied topic"
  }

  assert {
    condition     = output.alarm_topic_arn == "arn:aws:sns:eu-west-2:111111111111:existing"
    error_message = "The supplied topic should be exported"
  }
}

run "load_balancer_alarms" {
  command = apply

  variables {
    topology = "hub"
    groups = {
      platform-engineers = {
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
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.current) == 6
    error_message = "Two load balancer alarms should be added per endpoint with targets"
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].metric_name == "HealthyHostCount",
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].statistic == "Minimum",
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].threshold == 1,
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].evaluation_periods == 2,
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].treat_missing_data == "breaching",
    ])
    error_message = "The no healthy targets alarm should fire below one healthy target for two minutes"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].dimensions["TargetGroup"] == aws_lb_target_group.current["app-ssh"].arn_suffix
    error_message = "The load balancer alarms should watch the endpoint's target group"
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.current["app-ssh-unhealthy-targets"].metric_name == "UnHealthyHostCount",
      aws_cloudwatch_metric_alarm.current["app-ssh-unhealthy-targets"].statistic == "Maximum",
      aws_cloudwatch_metric_alarm.current["app-ssh-unhealthy-targets"].threshold == 0,
      aws_cloudwatch_metric_alarm.current["app-ssh-unhealthy-targets"].evaluation_periods == 5,
    ])
    error_message = "The unhealthy targets alarm should fire on any unhealthy target for five minutes"
  }
}

run "alarms_disabled" {
  command = plan

  variables {
    alarms = null
  }

  assert {
    condition     = length(aws_sns_topic.alarms) == 0 && length(aws_cloudwatch_metric_alarm.current) == 0 && length(aws_cloudwatch_event_rule.changed_outside_pipeline) == 0
    error_message = "No alarm resources should be created when alarms are disabled"
  }

  assert {
    condition     = output.alarm_topic_arn == null
    error_message = "The alarm topic output should be null when alarms are disabled"
  }
}

run "customised_alarms" {
  command = apply

  variables {
    topology = "hub"
    alarms = {
      additional_action_arns = ["arn:aws:sns:eu-west-2:111111111111:pagerduty"]
      pipeline_role_name     = "verified-access-pipeline"
      rules = {
        access-denied            = { enabled = false }
        unhealthy-targets        = { enabled = false }
        http-504                 = { threshold = 25, period = 60, evaluation_periods = 3, treat_missing_data = "missing" }
        no-healthy-targets       = { evaluation_periods = 5 }
        changed-outside-pipeline = { enabled = false }
      }
    }
    groups = {
      platform-engineers = {
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
        }
      }
    }
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.current)) == toset(["http-504", "logging-stopped", "no-access-allowed", "app-ssh-no-healthy-targets"])
    error_message = "Alarms turned off in rules should not be created"
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.current["http-504"].threshold == 25,
      aws_cloudwatch_metric_alarm.current["http-504"].period == 60,
      aws_cloudwatch_metric_alarm.current["http-504"].evaluation_periods == 3,
      aws_cloudwatch_metric_alarm.current["http-504"].treat_missing_data == "missing",
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].evaluation_periods == 5,
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].period == 60,
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].threshold == 1,
      aws_cloudwatch_metric_alarm.current["logging-stopped"].period == 3600,
    ])
    error_message = "Rules should win over the defaults, leaving the unset settings unchanged"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.changed_outside_pipeline) == 0 && length(aws_cloudwatch_event_target.changed_outside_pipeline) == 0
    error_message = "The changed outside the pipeline rule should be turned off by its rule, even with pipeline_role_name"
  }

  assert {
    condition = alltrue([
      for alarm in aws_cloudwatch_metric_alarm.current : toset(alarm.alarm_actions) == toset([aws_sns_topic.alarms[0].arn, "arn:aws:sns:eu-west-2:111111111111:pagerduty"]) && toset(alarm.ok_actions) == toset(alarm.alarm_actions)
    ])
    error_message = "Every alarm should notify the topic and the additional actions, on alarm and on recovery"
  }
}

run "endpoint_rules" {
  command = apply

  variables {
    topology = "hub"
    alarms = {
      rules = {
        no-healthy-targets           = { evaluation_periods = 5 }
        "app-ssh/no-healthy-targets" = { threshold = 2 }
        "app-web/no-healthy-targets" = { enabled = false }
        unhealthy-targets            = { enabled = false }
        "app-web/unhealthy-targets"  = { enabled = true, threshold = 1 }
      }
    }
    groups = {
      platform-engineers = {
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
            type        = "load-balancer"
            port_ranges = [{ from_port = 8080, to_port = 8080 }]
            targets     = ["10.50.0.20"]
          }
        }
      }
    }
  }

  assert {
    condition     = toset([for key in keys(aws_cloudwatch_metric_alarm.current) : key if strcontains(key, "targets")]) == toset(["app-ssh-no-healthy-targets", "app-web-unhealthy-targets"])
    error_message = "An <endpoint>/<alarm> rule should turn one endpoint's alarm off, or back on, over the rule for every endpoint"
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].threshold == 2,
      aws_cloudwatch_metric_alarm.current["app-ssh-no-healthy-targets"].evaluation_periods == 5,
      aws_cloudwatch_metric_alarm.current["app-web-unhealthy-targets"].threshold == 1,
      aws_cloudwatch_metric_alarm.current["app-web-unhealthy-targets"].evaluation_periods == 5,
    ])
    error_message = "An endpoint rule should win over the rule for every endpoint, which wins over the defaults"
  }
}

run "custom_alarms" {
  command = apply

  variables {
    topology = "hub"
    alarms = {
      custom = {
        denied-burst = {
          metric              = "access-denied"
          comparison_operator = "GreaterThanThreshold"
          threshold           = 100
          period              = 60
        }
        app-ssh-connections = {
          metric              = "app-ssh/unhealthy-host-count"
          comparison_operator = "GreaterThanOrEqualToThreshold"
          threshold           = 1
          statistic           = "Maximum"
          evaluation_periods  = 3
          description         = "An SSH host is unhealthy"
        }
      }
    }
    groups = {
      platform-engineers = {
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
        }
      }
    }
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.custom["denied-burst"].alarm_name == "verified-access-test-denied-burst",
      aws_cloudwatch_metric_alarm.custom["denied-burst"].namespace == "VerifiedAccess/test",
      aws_cloudwatch_metric_alarm.custom["denied-burst"].metric_name == "AccessDenied",
      aws_cloudwatch_metric_alarm.custom["denied-burst"].statistic == "Sum",
      aws_cloudwatch_metric_alarm.custom["denied-burst"].period == 60,
      aws_cloudwatch_metric_alarm.custom["denied-burst"].treat_missing_data == "missing",
      length(aws_cloudwatch_metric_alarm.custom["denied-burst"].dimensions) == 0,
    ])
    error_message = "A custom alarm on a log derived metric should watch the metric in the module namespace"
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.custom["app-ssh-connections"].namespace == "AWS/NetworkELB",
      aws_cloudwatch_metric_alarm.custom["app-ssh-connections"].metric_name == "UnHealthyHostCount",
      aws_cloudwatch_metric_alarm.custom["app-ssh-connections"].dimensions["TargetGroup"] == aws_lb_target_group.current["app-ssh"].arn_suffix,
      aws_cloudwatch_metric_alarm.custom["app-ssh-connections"].dimensions["LoadBalancer"] == aws_lb.current[0].arn_suffix,
      aws_cloudwatch_metric_alarm.custom["app-ssh-connections"].alarm_description == "An SSH host is unhealthy",
      aws_cloudwatch_metric_alarm.custom["app-ssh-connections"].evaluation_periods == 3,
    ])
    error_message = "A custom alarm on an endpoint metric should watch the endpoint's target group"
  }

  assert {
    condition     = alltrue([for alarm in aws_cloudwatch_metric_alarm.custom : contains(alarm.alarm_actions, aws_sns_topic.alarms[0].arn) && contains(alarm.ok_actions, aws_sns_topic.alarms[0].arn)])
    error_message = "Custom alarms should notify the topic, on alarm and on recovery"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.current) == 6
    error_message = "Custom alarms should be added to the module alarms"
  }
}
