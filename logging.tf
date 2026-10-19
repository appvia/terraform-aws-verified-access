locals {
  ## Indicates access logging is configured
  enable_access_logs = var.access_logs != null
  ## Indicates access logs are delivered to CloudWatch Logs
  enable_cloudwatch_logs = local.enable_access_logs ? var.access_logs.cloudwatch != null : false
  ## The log derived metrics created, by key: the chosen ones, or all of them
  selected_log_metrics = !local.enable_cloudwatch_logs ? [] : (
    var.access_logs.cloudwatch.metric_filters == null ? keys(local.log_metrics) : var.access_logs.cloudwatch.metric_filters
  )
  ## Indicates log derived metric filters are created
  enable_metric_filters = length(local.selected_log_metrics) > 0
  ## Indicates the saved Logs Insights queries are created
  enable_queries = local.enable_cloudwatch_logs ? var.access_logs.cloudwatch.create_queries : false
  ## Indicates the module creates the CloudWatch log group, rather than delivering to an existing one
  enable_log_group = local.enable_cloudwatch_logs ? var.access_logs.cloudwatch.create : false
  ## The name of the CloudWatch log group for the access logs
  log_group_name = local.enable_cloudwatch_logs ? coalesce(var.access_logs.cloudwatch.log_group_name, format("/aws/%s/%s", var.name_prefix, var.name)) : null
  ## The log group the logs, metric filters and queries use: the created one (so it exists first), or the existing one
  access_log_group = local.enable_log_group ? aws_cloudwatch_log_group.access_logs[0].name : local.log_group_name
  ## Indicates the module creates the key encrypting the log group
  enable_log_group_kms_key = local.enable_log_group ? var.access_logs.cloudwatch.create_kms_key : false
  ## The key encrypting the created log group: the created one, the supplied one, or none
  log_group_kms_key_arn = !local.enable_log_group ? null : (
    local.enable_log_group_kms_key ? aws_kms_key.access_logs[0].arn : var.access_logs.cloudwatch.kms_key_arn
  )

  ## Indicates access logs are delivered to S3
  enable_s3_logs = local.enable_access_logs ? var.access_logs.s3 != null : false
  ## Indicates the module creates the access log bucket
  enable_access_log_bucket = local.enable_s3_logs ? var.access_logs.s3.create : false
  ## The prefix of the log objects with a trailing slash, or empty
  access_log_prefix = local.enable_s3_logs && try(var.access_logs.s3.prefix, null) != null ? format("%s/", trimsuffix(var.access_logs.s3.prefix, "/")) : ""
  ## The bucket receiving the access logs: the created one, delivered to once its policy permits log delivery (so
  ## Verified Access does not add a policy of its own), or the existing one
  access_log_bucket_name = !local.enable_s3_logs ? null : (
    local.enable_access_log_bucket ? aws_s3_bucket_policy.access_logs[0].bucket : var.access_logs.s3.bucket_name
  )

  ## Indicates access logs are delivered to Kinesis Data Firehose
  enable_firehose_logs = local.enable_access_logs ? var.access_logs.firehose != null : false
  ## Indicates the module creates the Firehose delivery stream for the access logs
  enable_access_log_firehose = local.enable_firehose_logs ? var.access_logs.firehose.create : false
  ## The delivery stream receiving the access logs: the created one, or the named existing one
  firehose_delivery_stream_name = !local.enable_firehose_logs ? null : (
    local.enable_access_log_firehose ? aws_kinesis_firehose_delivery_stream.access_logs[0].name : var.access_logs.firehose.delivery_stream_name
  )
  ## The CloudWatch metric namespace for the log derived metrics
  metric_namespace = format("VerifiedAccess/%s", local.resource_name)

  ## The log derived metrics, by key: Verified Access publishes no CloudWatch metrics of its own
  ## (https://docs.aws.amazon.com/verified-access/latest/ug/monitoring-overview.html), so each is a metric filter
  log_metrics = {
    access-allowed = { metric_name = "AccessAllowed", description = "Requests and connections Verified Access allowed" }
    access-denied  = { metric_name = "AccessDenied", description = "Requests and connections Verified Access denied: a policy change gone wrong, or probing" }
    http-504       = { metric_name = "Http504", description = "HTTP 504 responses: the application is slower than the 60 second Verified Access limit" }
    http-5xx       = { metric_name = "Http5xx", description = "HTTP 5xx responses from the application or Verified Access" }
  }

  ## The metric filters of each log derived metric, keyed as before; HTTP and TCP entries carry the decision in
  ## different places (actor.authorizations vs data.authorizations)
  metric_filters = {
    allowed-http = { metric = "access-allowed", pattern = "{ $.actor.authorizations[0].decision = \"Allow\" }" }
    allowed-tcp  = { metric = "access-allowed", pattern = "{ $.data.authorizations[0].decision = \"Allow\" }" }
    denied-http  = { metric = "access-denied", pattern = "{ $.actor.authorizations[0].decision != \"Allow\" }" }
    denied-tcp   = { metric = "access-denied", pattern = "{ $.data.authorizations[0].decision != \"Allow\" }" }
    http-504     = { metric = "http-504", pattern = "{ $.http_response.code = 504 }" }
    http-5xx     = { metric = "http-5xx", pattern = "{ $.http_response.code >= 500 }" }
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

## Provision the key encrypting the access log group, when requested. The key policy permits CloudWatch Logs in this
## region to use it only for this log group (the log group ARN is the encryption context), as AWS documents
resource "aws_kms_key" "access_logs" {
  count = local.enable_log_group_kms_key ? 1 : 0

  deletion_window_in_days = 30
  description             = format("Encrypts the Verified Access %s access log group", var.name)
  enable_key_rotation     = true
  tags                    = merge(local.tags, { Name = format("%s-access-logs", local.resource_name) })

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
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:Describe*", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
        Resource  = "*"
        Principal = { Service = format("logs.%s.amazonaws.com", data.aws_region.current.region) }
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = format(
              "arn:%s:logs:%s:%s:log-group:%s",
              data.aws_partition.current.partition,
              data.aws_region.current.region,
              data.aws_caller_identity.current.account_id,
              local.log_group_name,
            )
          }
        }
      }
    ]
  })
}

## Name the access log group key so it can be found in the console
resource "aws_kms_alias" "access_logs" {
  count = local.enable_log_group_kms_key ? 1 : 0

  name          = format("alias/%s-access-logs", local.resource_name)
  target_key_id = aws_kms_key.access_logs[0].key_id
}

## Provision the CloudWatch log group so retention (personal data) is always bounded, unless an existing one is used
resource "aws_cloudwatch_log_group" "access_logs" {
  count = local.enable_log_group ? 1 : 0

  kms_key_id        = local.log_group_kms_key_arn
  name              = local.log_group_name
  retention_in_days = var.access_logs.cloudwatch.retention_in_days
  tags              = local.tags
}

## Configure where the instance delivers its access logs
resource "aws_verifiedaccess_instance_logging_configuration" "current" {
  count = local.enable_access_logs ? 1 : 0

  verifiedaccess_instance_id = local.instance_id

  access_logs {
    include_trust_context = var.access_logs.include_trust_context
    log_version           = var.access_logs.log_version

    cloudwatch_logs {
      enabled   = local.enable_cloudwatch_logs
      log_group = local.access_log_group
    }

    kinesis_data_firehose {
      delivery_stream = local.firehose_delivery_stream_name
      enabled         = local.firehose_delivery_stream_name != null
    }

    s3 {
      bucket_name  = local.access_log_bucket_name
      bucket_owner = try(var.access_logs.s3.bucket_owner, null)
      enabled      = local.enable_s3_logs
      prefix       = try(var.access_logs.s3.prefix, null)
    }
  }
}

## Provision the metric filters of the chosen log derived metrics
resource "aws_cloudwatch_log_metric_filter" "access" {
  for_each = { for key, filter in local.metric_filters : key => filter if contains(local.selected_log_metrics, filter.metric) }

  log_group_name = local.access_log_group
  name           = format("%s-%s", local.resource_name, each.key)
  pattern        = each.value.pattern

  metric_transformation {
    default_value = 0
    name          = local.log_metrics[each.value.metric].metric_name
    namespace     = local.metric_namespace
    unit          = "Count"
    value         = "1"
  }
}

## Provision the saved Logs Insights queries
resource "aws_cloudwatch_query_definition" "access" {
  for_each = local.enable_queries ? local.queries : {}

  log_group_names = [local.access_log_group]
  name            = format("%s/%s/%s", var.name_prefix, var.name, each.key)
  query_string    = each.value
}

## Provision the access log bucket, when requested. Object Lock can only be enabled when the bucket is created, so
## turning access_logs.s3.object_lock on or off later replaces the bucket (which Object Lock then prevents)
resource "aws_s3_bucket" "access_logs" {
  count = local.enable_access_log_bucket ? 1 : 0

  bucket              = coalesce(var.access_logs.s3.bucket_name, format("%s-access-logs-%s", local.resource_name, data.aws_caller_identity.current.account_id))
  force_destroy       = var.access_logs.s3.force_destroy
  object_lock_enabled = var.access_logs.s3.object_lock != null
  tags                = merge(local.tags, { Name = format("%s-access-logs", local.resource_name) })
}

## Block every form of public access to the access log bucket
resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = local.enable_access_log_bucket ? 1 : 0

  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.access_logs[0].id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

## Disable ACLs: the bucket owner owns every log object, whoever writes it
resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = local.enable_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

## Keep every version of the log objects; required by Object Lock, and protects against overwrites
resource "aws_s3_bucket_versioning" "access_logs" {
  count = local.enable_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

## Encrypt the log objects with the supplied customer managed key (SSE-KMS, with a bucket key to reduce KMS requests),
## or with S3 managed keys (SSE-S3); log delivery cannot use the AWS managed aws/s3 key
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = local.enable_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    bucket_key_enabled = var.access_logs.s3.kms_key_arn != null

    apply_server_side_encryption_by_default {
      kms_master_key_id = var.access_logs.s3.kms_key_arn
      sse_algorithm     = var.access_logs.s3.kms_key_arn != null ? "aws:kms" : "AES256"
    }
  }
}

## Expire the log objects after the retention period (personal data, so retention is bounded), their old versions a
## day later, and abandoned uploads after a week; locked objects are removed once their lock ends
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = local.enable_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket_versioning.access_logs[0].bucket

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = var.access_logs.s3.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

## Lock every new log object for the configured days, when requested
resource "aws_s3_bucket_object_lock_configuration" "access_logs" {
  count = local.enable_access_log_bucket && try(var.access_logs.s3.object_lock, null) != null ? 1 : 0

  bucket = aws_s3_bucket_versioning.access_logs[0].bucket

  rule {
    default_retention {
      days = var.access_logs.s3.object_lock.days
      mode = var.access_logs.s3.object_lock.mode
    }
  }
}

## Deny any request not made over TLS, and permit the log delivery service to write the access logs of this account,
## with the statements AWS adds for vended log delivery to S3 (scoped to this account's log sources)
resource "aws_s3_bucket_policy" "access_logs" {
  count = local.enable_access_log_bucket ? 1 : 0

  bucket = aws_s3_bucket_public_access_block.access_logs[0].bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Action    = "s3:*"
        Principal = "*"
        Resource  = [aws_s3_bucket.access_logs[0].arn, format("%s/*", aws_s3_bucket.access_logs[0].arn)]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Resource  = aws_s3_bucket.access_logs[0].arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnLike      = { "aws:SourceArn" = format("arn:%s:logs:%s:%s:*", data.aws_partition.current.partition, data.aws_region.current.region, data.aws_caller_identity.current.account_id) }
        }
      },
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Action    = "s3:PutObject"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Resource  = format("%s/%sAWSLogs/%s/*", aws_s3_bucket.access_logs[0].arn, local.access_log_prefix, data.aws_caller_identity.current.account_id)
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
          ArnLike = { "aws:SourceArn" = format("arn:%s:logs:%s:%s:*", data.aws_partition.current.partition, data.aws_region.current.region, data.aws_caller_identity.current.account_id) }
        }
      }
    ]
  })
}

## Provision the role the created delivery stream writes to its bucket with, trusted by Firehose in this account only
resource "aws_iam_role" "access_log_firehose" {
  count = local.enable_access_log_firehose ? 1 : 0

  description = format("Writes the Verified Access %s access logs from Firehose to S3", var.name)
  name        = format("%s-access-logs-firehose", local.resource_name)
  tags        = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "firehose.amazonaws.com" }
        Condition = { StringEquals = { "sts:ExternalId" = data.aws_caller_identity.current.account_id } }
      }
    ]
  })
}

## Permit the delivery stream role to write to the destination bucket only (and to use its key through S3)
resource "aws_iam_role_policy" "access_log_firehose" {
  count = local.enable_access_log_firehose ? 1 : 0

  name = "deliver-to-s3"
  role = aws_iam_role.access_log_firehose[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "WriteToBucket"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
        ]
        Resource = [var.access_logs.firehose.destination_bucket_arn, format("%s/*", var.access_logs.firehose.destination_bucket_arn)]
      }
      ], var.access_logs.firehose.kms_key_arn == null ? [] : [
      {
        Sid       = "EncryptObjects"
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = var.access_logs.firehose.kms_key_arn
        Condition = { StringEquals = { "kms:ViaService" = format("s3.%s.amazonaws.com", data.aws_region.current.region) } }
      }
    ])
  })
}

## Provision the delivery stream for the access logs, writing compressed objects to the destination bucket. Verified
## Access delivers through the log delivery service linked role, which may only write to streams tagged
## LogDeliveryEnabled = true; AWS adds the tag when logging is configured, so the module sets it to avoid drift
resource "aws_kinesis_firehose_delivery_stream" "access_logs" {
  count = local.enable_access_log_firehose ? 1 : 0

  destination = "extended_s3"
  name        = coalesce(var.access_logs.firehose.delivery_stream_name, format("%s-access-logs", local.resource_name))
  tags        = merge(local.tags, { LogDeliveryEnabled = "true" })

  extended_s3_configuration {
    bucket_arn          = var.access_logs.firehose.destination_bucket_arn
    buffering_interval  = var.access_logs.firehose.buffering_interval
    buffering_size      = var.access_logs.firehose.buffering_size
    compression_format  = "GZIP"
    error_output_prefix = format("%serrors/", var.access_logs.firehose.prefix == null ? "" : format("%s/", trimsuffix(var.access_logs.firehose.prefix, "/")))
    kms_key_arn         = var.access_logs.firehose.kms_key_arn
    prefix              = var.access_logs.firehose.prefix == null ? null : format("%s/", trimsuffix(var.access_logs.firehose.prefix, "/"))
    role_arn            = aws_iam_role.access_log_firehose[0].arn
  }

  server_side_encryption {
    enabled  = true
    key_type = "AWS_OWNED_CMK"
  }

  ## The role must be permitted to write before the stream is created, or the first deliveries fail
  depends_on = [aws_iam_role_policy.access_log_firehose]
}
