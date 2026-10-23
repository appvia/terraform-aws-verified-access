
## Provision the security group for the endpoint network interfaces, permitting traffic only to its targets on its
## ports, unless the endpoint uses only the supplied security groups
resource "aws_security_group" "current" {
  count = var.create_security_group ? 1 : 0

  name        = format("%s-%s", var.name_prefix, var.name)
  description = format("Verified Access endpoint %s", var.name)
  tags        = merge(var.tags, { Name = format("%s-%s", var.name_prefix, var.name) })
  vpc_id      = var.vpc_id

  dynamic "egress" {
    for_each = local.egress_rules

    content {
      cidr_blocks = [egress.value.cidr_ipv4]
      description = format("Verified Access endpoint %s to its targets", var.name)
      from_port   = egress.value.from_port
      protocol    = "tcp"
      to_port     = egress.value.to_port
    }
  }
}

## Provision the Verified Access endpoint
resource "aws_verifiedaccess_endpoint" "current" {
  application_domain       = var.application_domain
  attachment_type          = "vpc"
  description              = var.description
  domain_certificate_arn   = var.domain_certificate_arn
  endpoint_domain_prefix   = coalesce(var.endpoint_domain_prefix, var.name)
  endpoint_type            = var.type
  policy_document          = var.policy_document
  security_group_ids       = concat(aws_security_group.current[*].id, var.security_group_ids)
  tags                     = merge(var.tags, { Name = format("%s-%s", var.name_prefix, var.name) })
  verified_access_group_id = var.group_id

  dynamic "load_balancer_options" {
    for_each = var.type == "load-balancer" ? [true] : []

    content {
      load_balancer_arn = var.load_balancer_arn
      port              = local.enable_port_ranges ? null : var.port
      protocol          = var.protocol
      subnet_ids        = var.subnet_ids

      dynamic "port_range" {
        for_each = local.enable_port_ranges ? var.port_ranges : []

        content {
          from_port = port_range.value.from_port
          to_port   = port_range.value.to_port
        }
      }
    }
  }

  dynamic "network_interface_options" {
    for_each = var.type == "network-interface" ? [true] : []

    content {
      network_interface_id = var.network_interface_id
      port                 = local.enable_port_ranges ? null : var.port
      protocol             = var.protocol

      dynamic "port_range" {
        for_each = local.enable_port_ranges ? var.port_ranges : []

        content {
          from_port = port_range.value.from_port
          to_port   = port_range.value.to_port
        }
      }
    }
  }

  dynamic "cidr_options" {
    for_each = var.type == "cidr" ? [true] : []

    content {
      cidr       = var.cidr
      protocol   = "tcp"
      subnet_ids = var.subnet_ids

      dynamic "port_range" {
        for_each = var.port_ranges

        content {
          from_port = port_range.value.from_port
          to_port   = port_range.value.to_port
        }
      }
    }
  }

  dynamic "rds_options" {
    for_each = var.type == "rds" ? [true] : []

    content {
      port                = var.port
      protocol            = "tcp"
      rds_db_cluster_arn  = var.rds.cluster_arn
      rds_db_instance_arn = var.rds.instance_arn
      rds_db_proxy_arn    = var.rds.proxy_arn
      rds_endpoint        = var.rds.endpoint
      subnet_ids          = var.subnet_ids
    }
  }

  dynamic "sse_specification" {
    for_each = var.kms_key_arn != null ? [true] : []

    content {
      customer_managed_key_enabled = true
      kms_key_arn                  = var.kms_key_arn
    }
  }
}

## The security group is created with count since create_security_group was added; move the state of endpoints made
## before, so upgrading does not replace the security group (and with it the endpoint)
moved {
  from = aws_security_group.current
  to   = aws_security_group.current[0]
}
