locals {
  ## Indicates a web ACL is associated with the instance
  enable_waf = var.waf != null
  ## Indicates the module creates the web ACL
  enable_web_acl = local.enable_waf ? var.waf.create : false
  ## The web ACL associated with the instance
  web_acl_arn = !local.enable_waf ? null : (
    local.enable_web_acl ? aws_wafv2_web_acl.current[0].arn : var.waf.web_acl_arn
  )
  ## The ARN of the instance; the instance resource does not export one
  instance_arn = format(
    "arn:%s:ec2:%s:%s:verified-access-instance/%s",
    data.aws_partition.current.partition,
    data.aws_region.current.region,
    data.aws_caller_identity.current.account_id,
    aws_verifiedaccess_instance.current.id,
  )
  ## The AWS managed rule groups in the created web ACL, by priority
  web_acl_rule_groups = {
    AWSManagedRulesAmazonIpReputationList = 10
    AWSManagedRulesCommonRuleSet          = 20
    AWSManagedRulesKnownBadInputsRuleSet  = 30
  }
}

## Provision a regional web ACL with AWS managed rule groups, inspecting requests to the http and https endpoints
resource "aws_wafv2_web_acl" "current" {
  count = local.enable_web_acl ? 1 : 0

  description = format("Verified Access %s", var.name)
  name        = local.resource_name
  scope       = "REGIONAL"
  tags        = merge(local.tags, { Name = local.resource_name })

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.web_acl_rule_groups

    content {
      name     = rule.key
      priority = rule.value

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = format("%s-%s", local.resource_name, rule.key)
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.resource_name
    sampled_requests_enabled   = true
  }
}

## Associate the web ACL with the Verified Access instance
resource "aws_wafv2_web_acl_association" "current" {
  count = local.enable_waf ? 1 : 0

  resource_arn = local.instance_arn
  web_acl_arn  = local.web_acl_arn
}
