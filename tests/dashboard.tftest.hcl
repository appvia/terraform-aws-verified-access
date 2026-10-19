## Dashboard and metric stream tests: the headline widgets, the load balancer widget with topology hub, and the stream
## of the log derived and load balancer metrics.

mock_provider "aws" {
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

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-2"
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

  dashboard = {}

  groups = {}
}

run "single_vpc_dashboard" {
  command = plan

  assert {
    condition     = aws_cloudwatch_dashboard.current[0].dashboard_name == "verified-access-test"
    error_message = "The dashboard should be named verified-access-<name>"
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.current[0].dashboard_body).widgets) == 3
    error_message = "The dashboard should show access decisions, HTTP errors and who is connecting"
  }

  assert {
    condition = alltrue([
      for metric in ["AccessAllowed", "AccessDenied", "Http504", "Http5xx"] :
      strcontains(aws_cloudwatch_dashboard.current[0].dashboard_body, format("[\"VerifiedAccess/test\",\"%s\"", metric))
    ])
    error_message = "The dashboard should show the four log derived metrics"
  }

  assert {
    condition     = startswith(jsondecode(aws_cloudwatch_dashboard.current[0].dashboard_body).widgets[2].properties.query, "SOURCE '/aws/verified-access/test' | fields @timestamp")
    error_message = "The who is connecting widget should query the access log group"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.current[0].dashboard_body).widgets[0].properties.period == 300
    error_message = "The metric widgets should default to a five minute period"
  }

  assert {
    condition     = output.dashboard_name == "verified-access-test"
    error_message = "The dashboard name should be exported"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_stream.current) == 0
    error_message = "No metric stream should be created by default"
  }
}

run "hub_dashboard_and_metric_stream" {
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
    metric_stream = {
      firehose_arn = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/observability"
      role_arn     = "arn:aws:iam::111111111111:role/metric-stream"
    }
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.current[0].dashboard_body).widgets) == 4
    error_message = "The dashboard should add the load balancer health widget with topology hub"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.current[0].dashboard_body).widgets[2].properties.metrics[0][3] == "targetgroup/verified-access/0123456789abcdef"
    error_message = "The load balancer widget should show healthy targets per target group"
  }

  assert {
    condition     = aws_cloudwatch_metric_stream.current[0].name == "verified-access-test" && aws_cloudwatch_metric_stream.current[0].output_format == "opentelemetry1.0"
    error_message = "The metric stream should be named verified-access-<name> and default to OpenTelemetry 1.0"
  }

  assert {
    condition     = aws_cloudwatch_metric_stream.current[0].firehose_arn == "arn:aws:firehose:eu-west-2:111111111111:deliverystream/observability"
    error_message = "The metric stream should deliver to the supplied Firehose stream"
  }

  assert {
    condition = length(aws_cloudwatch_metric_stream.current[0].include_filter) == 2 && alltrue([
      for namespace in ["VerifiedAccess/test", "AWS/NetworkELB"] : anytrue([for filter in aws_cloudwatch_metric_stream.current[0].include_filter : filter.namespace == namespace])
    ])
    error_message = "The metric stream should include the log derived and load balancer namespaces"
  }
}

run "single_vpc_metric_stream" {
  command = plan

  variables {
    metric_stream = {
      firehose_arn  = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/observability"
      role_arn      = "arn:aws:iam::111111111111:role/metric-stream"
      output_format = "json"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_stream.current[0].include_filter) == 1 && anytrue([for filter in aws_cloudwatch_metric_stream.current[0].include_filter : filter.namespace == "VerifiedAccess/test"])
    error_message = "Without the central load balancer only the log derived namespace should be streamed"
  }
}

run "metric_stream_created_role" {
  command = apply

  variables {
    metric_stream = {
      firehose_arn = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/observability"
      create_role  = true
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }

  override_resource {
    target = aws_iam_role.metric_stream
    values = { arn = "arn:aws:iam::111111111111:role/verified-access-test-metric-stream" }
  }

  assert {
    condition     = aws_iam_role.metric_stream[0].name == "verified-access-test-metric-stream"
    error_message = "The role should be named <name_prefix>-<name>-metric-stream"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.metric_stream[0].assume_role_policy).Statement[0].Principal.Service == "streams.metrics.cloudwatch.amazonaws.com" &&
      jsondecode(aws_iam_role.metric_stream[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
    )
    error_message = "The role should be trusted by CloudWatch metric streams in this account only"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.metric_stream[0].policy).Statement[0].Resource == "arn:aws:firehose:eu-west-2:111111111111:deliverystream/observability" &&
      jsondecode(aws_iam_role_policy.metric_stream[0].policy).Statement[0].Action == ["firehose:PutRecord", "firehose:PutRecordBatch"]
    )
    error_message = "The role should only write to the delivery stream"
  }

  assert {
    condition     = aws_cloudwatch_metric_stream.current[0].role_arn == aws_iam_role.metric_stream[0].arn && output.metric_stream_role_arn == aws_iam_role.metric_stream[0].arn
    error_message = "The metric stream should use the created role, which is exported"
  }
}

run "metric_stream_supplied_role" {
  command = plan

  variables {
    metric_stream = {
      firehose_arn = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/observability"
      role_arn     = "arn:aws:iam::111111111111:role/metric-stream"
    }
  }

  assert {
    condition     = length(aws_iam_role.metric_stream) == 0 && output.metric_stream_role_arn == "arn:aws:iam::111111111111:role/metric-stream"
    error_message = "No role should be created when one is supplied"
  }
}

run "metric_stream_include" {
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
    metric_stream = {
      firehose_arn = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/observability"
      role_arn     = "arn:aws:iam::111111111111:role/metric-stream"
      include      = ["access-denied", "http-504", "app-ssh/healthy-host-count", "app-ssh/unhealthy-host-count", "load-balancer-processed-bytes", "incoming-log-events"]
    }
  }

  assert {
    condition = {
      for filter in aws_cloudwatch_metric_stream.current[0].include_filter : filter.namespace => toset(filter.metric_names)
      } == {
      "VerifiedAccess/test" = toset(["AccessDenied", "Http504"])
      "AWS/NetworkELB"      = toset(["HealthyHostCount", "ProcessedBytes", "UnHealthyHostCount"])
      "AWS/Logs"            = toset(["IncomingLogEvents"])
    }
    error_message = "The metric stream should include only the chosen metrics, by namespace and metric name"
  }
}

run "metrics_output" {
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
    condition = toset(keys(output.metrics)) == toset([
      "access-allowed", "access-denied", "http-504", "http-5xx", "incoming-log-events", "incoming-bytes",
      "load-balancer-active-flow-count", "load-balancer-new-flow-count", "load-balancer-processed-bytes",
      "load-balancer-tcp-client-reset-count", "load-balancer-tcp-target-reset-count", "load-balancer-tcp-elb-reset-count",
      "load-balancer-port-allocation-error-count",
      "app-ssh/healthy-host-count", "app-ssh/unhealthy-host-count",
    ])
    error_message = "The metrics output should list every metric the module makes available"
  }

  assert {
    condition = (
      output.metrics["app-ssh/healthy-host-count"].namespace == "AWS/NetworkELB" &&
      output.metrics["app-ssh/healthy-host-count"].metric_name == "HealthyHostCount" &&
      output.metrics["app-ssh/healthy-host-count"].dimensions["TargetGroup"] == "targetgroup/verified-access/0123456789abcdef" &&
      output.metrics["app-ssh/healthy-host-count"].dimensions["LoadBalancer"] == "net/verified-access-test/0123456789abcdef" &&
      output.metrics["load-balancer-processed-bytes"].dimensions == { LoadBalancer = "net/verified-access-test/0123456789abcdef" } &&
      output.metrics["http-504"].source == "log metric filter" && output.metrics["http-504"].statistic == "Sum"
    )
    error_message = "Each metric should carry its namespace, name, dimensions, recommended statistic and source"
  }
}

run "dashboard_disabled" {
  command = plan

  variables {
    dashboard = null
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.current) == 0 && output.dashboard_name == null
    error_message = "No dashboard should be created when disabled"
  }
}
