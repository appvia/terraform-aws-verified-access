## Logging wiring tests: the access log destinations, versions, retention and log derived metrics.

mock_provider "aws" {}

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

  groups = {}
}

run "cloudwatch_destination" {
  command = plan

  variables {
    access_logs = {
      cloudwatch = {}
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.access_logs[0].name == "/aws/verified-access/test"
    error_message = "The log group should default to /aws/verified-access/<name>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.access_logs[0].retention_in_days == 90
    error_message = "The log group retention should default to 90 days"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].cloudwatch_logs[0].enabled == true
    error_message = "CloudWatch logging should be enabled"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].cloudwatch_logs[0].log_group == "/aws/verified-access/test"
    error_message = "The logging configuration should deliver to the module's log group"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].s3[0].enabled == false
    error_message = "S3 logging should be disabled"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].kinesis_data_firehose[0].enabled == false
    error_message = "Firehose logging should be disabled"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].log_version == "ocsf-1.0.0-rc.2"
    error_message = "The log version should default to ocsf-1.0.0-rc.2"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].include_trust_context == false
    error_message = "Trust context (personal data) should be opt-in"
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.access) == 6
    error_message = "The six log derived metric filters should be created"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.access["denied-tcp"].metric_transformation[0].name == "AccessDenied"
    error_message = "TCP denials should feed the AccessDenied metric"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.access["http-504"].metric_transformation[0].namespace == "VerifiedAccess/test"
    error_message = "The metrics should be published to VerifiedAccess/<name>"
  }

  assert {
    condition     = length(aws_cloudwatch_query_definition.access) == 2
    error_message = "The saved Logs Insights queries should be created"
  }
}

run "cloudwatch_custom_settings" {
  command = plan

  variables {
    access_logs = {
      include_trust_context = true
      cloudwatch = {
        log_group_name        = "/custom/verified-access"
        retention_in_days     = 365
        kms_key_arn           = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
        enable_metric_filters = false
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.access_logs[0].name == "/custom/verified-access"
    error_message = "The log group name should be configurable"
  }

  assert {
    condition     = aws_cloudwatch_log_group.access_logs[0].retention_in_days == 365
    error_message = "The log group retention should be configurable"
  }

  assert {
    condition     = aws_cloudwatch_log_group.access_logs[0].kms_key_id == "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The log group should be encrypted with the supplied KMS key"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].include_trust_context == true
    error_message = "Trust context should be included when enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.access) == 0 && length(aws_cloudwatch_query_definition.access) == 0
    error_message = "Metric filters and queries should be opt-out"
  }
}

run "s3_destination" {
  command = plan

  variables {
    access_logs = {
      s3 = {
        bucket_name  = "log-archive-verified-access"
        bucket_owner = "418272759831"
        prefix       = "verified-access"
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.access_logs) == 0
    error_message = "No log group should be created without a CloudWatch destination"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].s3[0].enabled == true
    error_message = "S3 logging should be enabled"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].s3[0].bucket_name == "log-archive-verified-access"
    error_message = "S3 logging should deliver to the supplied bucket"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].s3[0].bucket_owner == "418272759831"
    error_message = "S3 logging should set the bucket owner for cross account delivery"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].cloudwatch_logs[0].enabled == false
    error_message = "CloudWatch logging should be disabled"
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.access) == 0
    error_message = "Metric filters need a CloudWatch destination"
  }
}

run "all_destinations" {
  command = plan

  variables {
    access_logs = {
      cloudwatch                    = {}
      s3                            = { bucket_name = "log-archive-verified-access" }
      firehose_delivery_stream_name = "siem"
    }
  }

  assert {
    condition = alltrue([
      aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].cloudwatch_logs[0].enabled,
      aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].s3[0].enabled,
      aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].kinesis_data_firehose[0].enabled,
    ])
    error_message = "All three destinations should be enabled"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].kinesis_data_firehose[0].delivery_stream == "siem"
    error_message = "Firehose logging should deliver to the supplied stream"
  }
}

run "logging_disabled" {
  command = plan

  variables {
    access_logs = null
  }

  ## The check block warns rather than blocks; terraform test reports it as a failure we expect
  expect_failures = [check.access_logs]

  assert {
    condition     = length(aws_verifiedaccess_instance_logging_configuration.current) == 0 && length(aws_cloudwatch_log_group.access_logs) == 0
    error_message = "No logging resources should be created when logging is disabled"
  }
}

run "existing_log_group" {
  command = plan

  variables {
    access_logs = {
      cloudwatch = {
        create_log_group = false
        log_group_name   = "/central/verified-access"
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.access_logs) == 0
    error_message = "No log group should be created when an existing one is used"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].cloudwatch_logs[0].log_group == "/central/verified-access"
    error_message = "The logs should be delivered to the existing log group"
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.access) == 6 && alltrue([for filter in aws_cloudwatch_log_metric_filter.access : filter.log_group_name == "/central/verified-access"])
    error_message = "The metric filters should be attached to the existing log group"
  }

  assert {
    condition     = alltrue([for query in aws_cloudwatch_query_definition.access : tolist(query.log_group_names) == tolist(["/central/verified-access"])])
    error_message = "The saved queries should query the existing log group"
  }

  assert {
    condition     = output.access_log_group_name == "/central/verified-access"
    error_message = "The existing log group should be exported"
  }
}
