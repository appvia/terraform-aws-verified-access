## Logging wiring tests: the access log destinations, versions, retention and log derived metrics, and the bucket,
## delivery stream and log group key the module creates on request.

mock_provider "aws" {
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

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::verified-access-test-access-logs-111111111111"
      id  = "verified-access-test-access-logs-111111111111"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/verified-access-test-access-logs-firehose"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
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
        log_group_name    = "/custom/verified-access"
        retention_in_days = 365
        kms_key_arn       = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
        metric_filters    = []
        create_queries    = false
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

  assert {
    condition     = output.metric_namespace == null && toset(keys(output.metrics)) == toset(["incoming-log-events", "incoming-bytes"])
    error_message = "Without metric filters only the log group metrics should be available"
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
      cloudwatch = {}
      s3         = { bucket_name = "log-archive-verified-access" }
      firehose   = { delivery_stream_name = "siem" }
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
        create         = false
        log_group_name = "/central/verified-access"
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

run "selected_metric_filters" {
  command = plan

  variables {
    access_logs = {
      cloudwatch = {
        metric_filters = ["access-denied", "http-504"]
      }
    }
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_metric_filter.access)) == toset(["denied-http", "denied-tcp", "http-504"])
    error_message = "Only the filters of the chosen metrics should be created"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.access["denied-tcp"].metric_transformation[0].name == "AccessDenied" && aws_cloudwatch_log_metric_filter.access["http-504"].metric_transformation[0].name == "Http504"
    error_message = "The filters should keep their metric names"
  }

  assert {
    condition     = length(aws_cloudwatch_query_definition.access) == 2
    error_message = "The saved queries should not depend on the metric filters"
  }

  assert {
    condition = (
      toset(keys(output.metrics)) == toset(["access-denied", "http-504", "incoming-log-events", "incoming-bytes"]) &&
      output.metrics["access-denied"].namespace == "VerifiedAccess/test" && output.metrics["access-denied"].source == "log metric filter" &&
      output.metrics["incoming-log-events"].dimensions["LogGroupName"] == "/aws/verified-access/test"
    )
    error_message = "The metrics output should list the chosen log derived metrics and the log group metrics"
  }
}

run "created_log_group_key" {
  command = apply

  variables {
    access_logs = {
      cloudwatch = {
        create_kms_key = true
      }
    }
  }

  assert {
    condition     = aws_kms_key.access_logs[0].enable_key_rotation == true && aws_kms_alias.access_logs[0].name == "alias/verified-access-test-access-logs"
    error_message = "A rotated key with the alias alias/<name_prefix>-<name>-access-logs should be created"
  }

  assert {
    condition     = aws_cloudwatch_log_group.access_logs[0].kms_key_id == aws_kms_key.access_logs[0].arn
    error_message = "The log group should be encrypted with the created key"
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_kms_key.access_logs[0].policy).Statement :
      statement.Principal == { Service = "logs.eu-west-2.amazonaws.com" } &&
      statement.Condition.ArnEquals["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:eu-west-2:111111111111:log-group:/aws/verified-access/test"
    ])
    error_message = "The key policy should permit CloudWatch Logs only for the access log group"
  }

  assert {
    condition     = output.access_log_kms_key_arn == aws_kms_key.access_logs[0].arn
    error_message = "The created key should be exported"
  }
}

run "created_bucket_defaults" {
  command = apply

  variables {
    access_logs = {
      s3 = {
        create = true
      }
    }
  }

  assert {
    condition     = aws_s3_bucket.access_logs[0].bucket == "verified-access-test-access-logs-111111111111"
    error_message = "The bucket should be named <name_prefix>-<name>-access-logs-<account id>"
  }

  assert {
    condition     = aws_s3_bucket.access_logs[0].object_lock_enabled == false && aws_s3_bucket.access_logs[0].force_destroy == false
    error_message = "Object lock and force destroy should be off by default"
  }

  assert {
    condition     = length(aws_s3_bucket_object_lock_configuration.access_logs) == 0
    error_message = "No object lock configuration should be created by default"
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.access_logs[0].block_public_acls,
      aws_s3_bucket_public_access_block.access_logs[0].block_public_policy,
      aws_s3_bucket_public_access_block.access_logs[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.access_logs[0].restrict_public_buckets,
    ])
    error_message = "Every form of public access should be blocked"
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.access_logs[0].rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs should be disabled"
  }

  assert {
    condition     = aws_s3_bucket_versioning.access_logs[0].versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.access_logs[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "The bucket should default to SSE-S3"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.access_logs[0].rule[0].expiration[0].days == 365
    error_message = "Log objects should expire after 365 days by default"
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.access_logs[0].policy).Statement :
      statement.Effect == "Deny" && statement.Condition.Bool["aws:SecureTransport"] == "false"
    ])
    error_message = "The bucket policy should deny requests without TLS"
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.access_logs[0].policy).Statement :
      statement.Sid == "AWSLogDeliveryWrite" &&
      statement.Principal == { Service = "delivery.logs.amazonaws.com" } &&
      statement.Resource == "arn:aws:s3:::verified-access-test-access-logs-111111111111/AWSLogs/111111111111/*" &&
      statement.Condition.StringEquals["aws:SourceAccount"] == "111111111111" &&
      statement.Condition.ArnLike["aws:SourceArn"] == "arn:aws:logs:eu-west-2:111111111111:*"
    ])
    error_message = "The bucket policy should permit log delivery from this account only"
  }

  assert {
    condition     = aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].s3[0].bucket_name == aws_s3_bucket.access_logs[0].bucket
    error_message = "The logs should be delivered to the created bucket"
  }

  assert {
    condition     = output.access_log_bucket_name == aws_s3_bucket.access_logs[0].bucket && output.access_log_bucket_arn == aws_s3_bucket.access_logs[0].arn
    error_message = "The created bucket should be exported"
  }
}

run "created_bucket_settings" {
  command = plan

  variables {
    access_logs = {
      s3 = {
        create         = true
        bucket_name    = "example-verified-access-logs"
        prefix         = "verified-access/"
        retention_days = 400
        object_lock    = { days = 30 }
        kms_key_arn    = "arn:aws:kms:eu-west-2:111111111111:key/11111111-1111-1111-1111-111111111111"
        force_destroy  = true
      }
    }
  }

  assert {
    condition     = aws_s3_bucket.access_logs[0].bucket == "example-verified-access-logs" && aws_s3_bucket.access_logs[0].force_destroy == true
    error_message = "The bucket name and force destroy should be configurable"
  }

  assert {
    condition     = aws_s3_bucket.access_logs[0].object_lock_enabled == true
    error_message = "Object lock should be enabled when the bucket is created"
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.access_logs[0].rule[0].default_retention[0].mode == "COMPLIANCE" && aws_s3_bucket_object_lock_configuration.access_logs[0].rule[0].default_retention[0].days == 30
    error_message = "Object lock should default to compliance mode for the configured days"
  }

  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.access_logs[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms" &&
      one(aws_s3_bucket_server_side_encryption_configuration.access_logs[0].rule).apply_server_side_encryption_by_default[0].kms_master_key_id == "arn:aws:kms:eu-west-2:111111111111:key/11111111-1111-1111-1111-111111111111"
    )
    error_message = "The bucket should be encrypted with the supplied key"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.access_logs[0].rule[0].expiration[0].days == 400
    error_message = "The retention should be configurable"
  }
}

run "created_bucket_prefix" {
  command = apply

  variables {
    access_logs = {
      s3 = {
        create = true
        prefix = "verified-access/"
      }
    }
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.access_logs[0].policy).Statement :
      statement.Sid == "AWSLogDeliveryWrite" && statement.Resource == "arn:aws:s3:::verified-access-test-access-logs-111111111111/verified-access/AWSLogs/111111111111/*"
    ])
    error_message = "Log delivery should be permitted under the prefix"
  }
}

run "created_firehose" {
  command = apply

  variables {
    access_logs = {
      firehose = {
        create                 = true
        destination_bucket_arn = "arn:aws:s3:::example-siem-intake"
        prefix                 = "verified-access"
        kms_key_arn            = "arn:aws:kms:eu-west-2:111111111111:key/11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.access_logs[0].name == "verified-access-test-access-logs" && aws_kinesis_firehose_delivery_stream.access_logs[0].destination == "extended_s3"
    error_message = "A delivery stream named <name_prefix>-<name>-access-logs should write to S3"
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.access_logs[0].tags["LogDeliveryEnabled"] == "true"
    error_message = "The stream should carry the tag the log delivery role requires"
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.access_logs[0].extended_s3_configuration[0].bucket_arn == "arn:aws:s3:::example-siem-intake" &&
      aws_kinesis_firehose_delivery_stream.access_logs[0].extended_s3_configuration[0].prefix == "verified-access/" &&
      aws_kinesis_firehose_delivery_stream.access_logs[0].extended_s3_configuration[0].role_arn == aws_iam_role.access_log_firehose[0].arn
    )
    error_message = "The stream should write to the destination bucket under the prefix with its role"
  }

  assert {
    condition     = jsondecode(aws_iam_role.access_log_firehose[0].assume_role_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == "111111111111"
    error_message = "The role should be assumable by Firehose in this account only"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.access_log_firehose[0].policy).Statement[0].Resource == ["arn:aws:s3:::example-siem-intake", "arn:aws:s3:::example-siem-intake/*"] &&
      length(jsondecode(aws_iam_role_policy.access_log_firehose[0].policy).Statement) == 2
    )
    error_message = "The role should write only to the destination bucket, and use the key"
  }

  assert {
    condition = (
      aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].kinesis_data_firehose[0].enabled &&
      aws_verifiedaccess_instance_logging_configuration.current[0].access_logs[0].kinesis_data_firehose[0].delivery_stream == "verified-access-test-access-logs"
    )
    error_message = "The logs should be delivered to the created stream"
  }

  assert {
    condition     = output.access_log_firehose_arn == aws_kinesis_firehose_delivery_stream.access_logs[0].arn && output.access_log_firehose_role_arn == aws_iam_role.access_log_firehose[0].arn
    error_message = "The created stream and role should be exported"
  }
}

run "created_firehose_named" {
  command = plan

  variables {
    access_logs = {
      firehose = {
        create                 = true
        delivery_stream_name   = "siem-verified-access"
        destination_bucket_arn = "arn:aws:s3:::example-siem-intake"
      }
    }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.access_logs[0].name == "siem-verified-access"
    error_message = "With create, delivery_stream_name should name the created stream, as bucket_name names a created bucket"
  }

  assert {
    condition     = length(aws_iam_role_policy.access_log_firehose) == 1
    error_message = "The created stream should have its role"
  }
}

run "nothing_created_by_default" {
  command = plan

  variables {
    access_logs = {
      cloudwatch = {}
      s3         = { bucket_name = "log-archive-verified-access" }
      firehose   = { delivery_stream_name = "siem" }
    }
  }

  assert {
    condition = (
      length(aws_s3_bucket.access_logs) == 0 && length(aws_kinesis_firehose_delivery_stream.access_logs) == 0 &&
      length(aws_iam_role.access_log_firehose) == 0 && length(aws_kms_key.access_logs) == 0
    )
    error_message = "No bucket, delivery stream, role or key should be created for existing destinations"
  }

  assert {
    condition     = output.access_log_bucket_name == "log-archive-verified-access" && output.access_log_bucket_arn == null && output.access_log_firehose_arn == null
    error_message = "The existing bucket name should be exported, and nothing created"
  }
}
