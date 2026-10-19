
## Provision the Verified Access instance, the container for trust providers, groups and endpoints, unless the groups
## and endpoints are added to an existing instance
resource "aws_verifiedaccess_instance" "current" {
  count = local.enable_instance ? 1 : 0

  cidr_endpoints_custom_subdomain = var.cidr_endpoints_custom_subdomain
  description                     = var.description
  fips_enabled                    = var.fips_enabled
  tags                            = merge(local.tags, { Name = var.name })
}

## Provision the user identity trust provider (IAM Identity Center or OIDC); an existing instance has its own
resource "aws_verifiedaccess_trust_provider" "user" {
  count = local.enable_instance ? 1 : 0

  description              = format("User identity trust provider for %s", var.name)
  policy_reference_name    = local.user_policy_reference
  tags                     = merge(local.tags, { Name = format("%s-user", var.name) })
  trust_provider_type      = "user"
  user_trust_provider_type = var.user_trust_provider.type

  dynamic "oidc_options" {
    for_each = var.user_trust_provider.type == "oidc" ? [var.user_trust_provider.oidc] : []

    content {
      authorization_endpoint = oidc_options.value.authorization_endpoint
      client_id              = oidc_options.value.client_id
      client_secret          = var.oidc_client_secret
      issuer                 = oidc_options.value.issuer
      scope                  = oidc_options.value.scope
      token_endpoint         = oidc_options.value.token_endpoint
      user_info_endpoint     = oidc_options.value.user_info_endpoint
    }
  }

  ## Native application options let the Connectivity Client (TCP) authenticate against the OIDC provider, with the
  ## browser client unless a separate native application client is configured
  dynamic "native_application_oidc_options" {
    for_each = var.user_trust_provider.type == "oidc" && try(var.user_trust_provider.oidc.public_signing_key_endpoint, null) != null ? [var.user_trust_provider.oidc] : []

    content {
      authorization_endpoint      = native_application_oidc_options.value.authorization_endpoint
      client_id                   = coalesce(native_application_oidc_options.value.native_client_id, native_application_oidc_options.value.client_id)
      client_secret               = var.oidc_native_client_secret != null ? var.oidc_native_client_secret : var.oidc_client_secret
      issuer                      = native_application_oidc_options.value.issuer
      public_signing_key_endpoint = native_application_oidc_options.value.public_signing_key_endpoint
      scope                       = coalesce(native_application_oidc_options.value.native_scope, native_application_oidc_options.value.scope)
      token_endpoint              = native_application_oidc_options.value.token_endpoint
      user_info_endpoint          = native_application_oidc_options.value.user_info_endpoint
    }
  }

  dynamic "sse_specification" {
    for_each = local.kms_key_arn != null ? [true] : []

    content {
      customer_managed_key_enabled = true
      kms_key_arn                  = local.kms_key_arn
    }
  }
}

## Provision the optional device posture trust provider
resource "aws_verifiedaccess_trust_provider" "device" {
  count = local.enable_device_trust_provider ? 1 : 0

  description                = format("Device trust provider for %s", var.name)
  device_trust_provider_type = var.device_trust_provider.type
  policy_reference_name      = local.device_policy_reference
  tags                       = merge(local.tags, { Name = format("%s-device", var.name) })
  trust_provider_type        = "device"

  device_options {
    tenant_id = var.device_trust_provider.tenant_id
  }

  dynamic "sse_specification" {
    for_each = local.kms_key_arn != null ? [true] : []

    content {
      customer_managed_key_enabled = true
      kms_key_arn                  = local.kms_key_arn
    }
  }
}

## Attach the user trust provider to the instance
resource "aws_verifiedaccess_instance_trust_provider_attachment" "user" {
  count = local.enable_instance ? 1 : 0

  verifiedaccess_instance_id       = aws_verifiedaccess_instance.current[0].id
  verifiedaccess_trust_provider_id = aws_verifiedaccess_trust_provider.user[0].id
}

## Attach the device trust provider to the instance
resource "aws_verifiedaccess_instance_trust_provider_attachment" "device" {
  count = local.enable_device_trust_provider ? 1 : 0

  verifiedaccess_instance_id       = aws_verifiedaccess_instance.current[0].id
  verifiedaccess_trust_provider_id = aws_verifiedaccess_trust_provider.device[0].id
}

## Provision the Verified Access groups and their rendered policies
module "groups" {
  for_each = var.groups
  source   = "./modules/group"

  description     = each.value.description
  instance_id     = local.instance_id
  kms_key_arn     = local.kms_key_arn
  name            = format("%s-%s", var.name, each.key)
  policy_document = local.group_policies[each.key]
  tags            = merge(local.tags, each.value.tags)

  ## Verified Access requires trust providers to be attached before groups are created; nothing in the group
  ## references the attachments, so the dependency is made explicit (an existing instance has them attached already)
  depends_on = [
    aws_verifiedaccess_instance_trust_provider_attachment.device,
    aws_verifiedaccess_instance_trust_provider_attachment.user,
  ]
}

## Provision the Verified Access endpoints, one per application; overridden subnets are read first, which checks they
## are in var.vpc_id
module "endpoints" {
  for_each = local.endpoints
  source   = "./modules/endpoint"

  application_domain     = each.value.application_domain
  cidr                   = each.value.cidr
  description            = each.value.description
  domain_certificate_arn = local.endpoint_targets[each.key].domain_certificate_arn
  egress_cidr_blocks     = local.endpoint_targets[each.key].egress_cidr_blocks
  create_security_group  = each.value.create_security_group
  endpoint_domain_prefix = coalesce(each.value.endpoint_domain_prefix, each.key)
  group_id               = module.groups[each.value.group].id
  kms_key_arn            = local.kms_key_arn
  load_balancer_arn      = local.endpoint_targets[each.key].load_balancer_arn
  name                   = format("%s-%s", var.name, each.key)
  name_prefix            = var.name_prefix
  network_interface_id   = each.value.network_interface_id
  policy_document        = lookup(local.endpoint_policies, each.key, null)
  port                   = local.endpoint_targets[each.key].port
  port_ranges            = local.endpoint_targets[each.key].port_ranges
  protocol               = each.value.protocol
  rds                    = each.value.rds
  security_group_ids     = each.value.security_group_ids
  subnet_ids             = each.value.subnet_ids != null ? [for id in each.value.subnet_ids : data.aws_subnet.endpoint[id].id] : var.subnet_ids
  tags                   = each.value.tags
  type                   = each.value.type
  vpc_id                 = var.vpc_id
}

## The instance, user trust provider and its attachment are created with count since existing_instance was added;
## move the state of deployments made before, so upgrading does not replace them
moved {
  from = aws_verifiedaccess_instance.current
  to   = aws_verifiedaccess_instance.current[0]
}

moved {
  from = aws_verifiedaccess_trust_provider.user
  to   = aws_verifiedaccess_trust_provider.user[0]
}

moved {
  from = aws_verifiedaccess_instance_trust_provider_attachment.user
  to   = aws_verifiedaccess_instance_trust_provider_attachment.user[0]
}

## Provision the key encrypting the trust providers, groups and endpoints, when requested. Verified Access uses the key
## through grants it creates on behalf of the caller, so the key policy permits any principal in this account to use
## it via Verified Access in this region, as AWS documents
resource "aws_kms_key" "current" {
  count = var.create_kms_key ? 1 : 0

  deletion_window_in_days = 30
  description             = format("Encrypts the Verified Access %s trust providers, groups and endpoints", var.name)
  enable_key_rotation     = true
  tags                    = merge(local.tags, { Name = local.resource_name })

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
        Sid       = "AllowVerifiedAccess"
        Effect    = "Allow"
        Action    = ["kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
        Resource  = "*"
        Principal = { AWS = "*" }
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
            "kms:ViaService"    = format("verified-access.%s.amazonaws.com", data.aws_region.current.region)
          }
        }
      }
    ]
  })
}

## Name the Verified Access key so it can be found in the console
resource "aws_kms_alias" "current" {
  count = var.create_kms_key ? 1 : 0

  name          = format("alias/%s", local.resource_name)
  target_key_id = aws_kms_key.current[0].key_id
}
