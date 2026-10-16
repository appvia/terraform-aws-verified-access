locals {
  ## Indicates the dashboard is created
  enable_dashboard = var.dashboard != null
  ## Indicates the metric stream is created
  enable_metric_stream = var.metric_stream != null
  ## The name of the dashboard
  dashboard_name = local.resource_name
}

## Provision the CloudWatch dashboard answering is it up, what is failing and who is connecting now: access decisions,
## HTTP errors, healthy targets per endpoint (topology hub) and the who-is-connecting query
resource "aws_cloudwatch_dashboard" "current" {
  count = local.enable_dashboard ? 1 : 0

  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            metrics = [
              [local.metric_namespace, "AccessAllowed", { label = "Allowed" }],
              [local.metric_namespace, "AccessDenied", { label = "Denied" }],
            ]
            period = var.dashboard.period
            region = data.aws_region.current.region
            stat   = "Sum"
            title  = "Access decisions"
            view   = "timeSeries"
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            metrics = [
              [local.metric_namespace, "Http504", { label = "HTTP 504" }],
              [local.metric_namespace, "Http5xx", { label = "HTTP 5xx" }],
            ]
            period = var.dashboard.period
            region = data.aws_region.current.region
            stat   = "Sum"
            title  = "HTTP errors"
            view   = "timeSeries"
          }
        },
      ],
      length(local.load_balancer_endpoints) == 0 ? [] : [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 24
          height = 6
          properties = {
            metrics = [
              for name, _ in local.load_balancer_endpoints : [
                "AWS/NetworkELB", "HealthyHostCount",
                "TargetGroup", aws_lb_target_group.current[name].arn_suffix,
                "LoadBalancer", aws_lb.current[0].arn_suffix,
                { label = name },
              ]
            ]
            period = 60
            region = data.aws_region.current.region
            stat   = "Minimum"
            title  = "Healthy targets per endpoint"
            view   = "timeSeries"
          }
        },
      ],
      [
        {
          type   = "log"
          x      = 0
          y      = 12
          width  = 24
          height = 8
          properties = {
            query  = format("SOURCE '%s' | %s", local.log_group_name, trimspace(local.queries["who-is-connecting"]))
            region = data.aws_region.current.region
            title  = "Who is connecting"
            view   = "table"
          }
        },
      ],
    )
  })
}

## Stream the log derived metrics and, with topology hub, the load balancer metrics to a Firehose delivery stream for
## an external observability platform. Include filters match whole namespaces, so AWS/NetworkELB carries every
## network load balancer in the account and region
resource "aws_cloudwatch_metric_stream" "current" {
  count = local.enable_metric_stream ? 1 : 0

  firehose_arn  = var.metric_stream.firehose_arn
  name          = local.resource_name
  output_format = var.metric_stream.output_format
  role_arn      = var.metric_stream.role_arn
  tags          = local.tags

  include_filter {
    namespace = local.metric_namespace
  }

  dynamic "include_filter" {
    for_each = local.enable_load_balancer ? ["AWS/NetworkELB"] : []

    content {
      namespace = include_filter.value
    }
  }
}
