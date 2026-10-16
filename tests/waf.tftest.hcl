## WAF tests: an existing web ACL or one created with AWS managed rule groups, associated with the instance.

mock_provider "aws" {
  mock_resource "aws_verifiedaccess_instance" {
    defaults = {
      id = "vai-0123456789abcdef0"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:eu-west-2:111111111111:regional/webacl/verified-access-test/11111111-1111-1111-1111-111111111111"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-2"
    }
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

  groups = {}
}

run "created_web_acl" {
  command = apply

  variables {
    waf = {
      create = true
    }
  }

  assert {
    condition     = aws_wafv2_web_acl.current[0].name == "verified-access-test" && aws_wafv2_web_acl.current[0].scope == "REGIONAL"
    error_message = "A regional web ACL named verified-access-<name> should be created"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.current[0].default_action[0].allow) == 1
    error_message = "The web ACL should allow requests the rules do not block"
  }

  assert {
    condition = length(aws_wafv2_web_acl.current[0].rule) == 3 && alltrue([
      for name in ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet", "AWSManagedRulesAmazonIpReputationList"] :
      anytrue([for rule in aws_wafv2_web_acl.current[0].rule : rule.statement[0].managed_rule_group_statement[0].name == name && rule.statement[0].managed_rule_group_statement[0].vendor_name == "AWS"])
    ])
    error_message = "The web ACL should use the AWS common, known bad inputs and IP reputation rule groups"
  }

  assert {
    condition     = aws_wafv2_web_acl.current[0].visibility_config[0].cloudwatch_metrics_enabled == true && alltrue([for rule in aws_wafv2_web_acl.current[0].rule : rule.visibility_config[0].cloudwatch_metrics_enabled])
    error_message = "The web ACL and its rules should publish CloudWatch metrics"
  }

  assert {
    condition     = aws_wafv2_web_acl_association.current[0].resource_arn == "arn:aws:ec2:eu-west-2:111111111111:verified-access-instance/vai-0123456789abcdef0"
    error_message = "The web ACL should be associated with the instance ARN"
  }

  assert {
    condition     = aws_wafv2_web_acl_association.current[0].web_acl_arn == aws_wafv2_web_acl.current[0].arn
    error_message = "The created web ACL should be associated"
  }

  assert {
    condition     = output.web_acl_arn == aws_wafv2_web_acl.current[0].arn
    error_message = "The web ACL should be exported"
  }
}

run "existing_web_acl" {
  command = plan

  variables {
    waf = {
      web_acl_arn = "arn:aws:wafv2:eu-west-2:111111111111:regional/webacl/shared/22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = length(aws_wafv2_web_acl.current) == 0
    error_message = "No web ACL should be created when one is supplied"
  }

  assert {
    condition     = aws_wafv2_web_acl_association.current[0].web_acl_arn == "arn:aws:wafv2:eu-west-2:111111111111:regional/webacl/shared/22222222-2222-2222-2222-222222222222"
    error_message = "The supplied web ACL should be associated"
  }
}

run "waf_disabled" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.current) == 0 && length(aws_wafv2_web_acl_association.current) == 0
    error_message = "No WAF resources should be created by default"
  }

  assert {
    condition     = output.web_acl_arn == null
    error_message = "The web ACL output should be null by default"
  }
}
