locals {
  ## Indicates the central load balancer is created (topology hub)
  enable_load_balancer = var.topology == "hub"
  ## The health check of target groups without their own: TCP on the traffic port
  default_health_check = {
    protocol            = "TCP"
    port                = "traffic-port"
    path                = null
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }
  ## The endpoints reaching services across the transit gateway through the central load balancer. Two ports matter:
  ## - target_port, the service port: the port of http and https endpoints, the single port range of tcp endpoints;
  ##   the target group and its targets use it unless a target sets its own
  ## - listener_port, defaulting to the target port: the listener on the central load balancer, which is also the
  ##   port the endpoint connects to and so the port clients use on the endpoint domain (tcp endpoints)
  load_balancer_endpoints = {
    for name, endpoint in local.endpoints : name => {
      listener_port        = coalesce(endpoint.listener_port, endpoint.protocol == "tcp" ? endpoint.port_ranges[0].from_port : endpoint.port)
      target_port          = endpoint.protocol == "tcp" ? endpoint.port_ranges[0].from_port : endpoint.port
      health_check         = endpoint.health_check != null ? endpoint.health_check : local.default_health_check
      deregistration_delay = coalesce(endpoint.deregistration_delay, 300)
      preserve_client_ip   = coalesce(endpoint.preserve_client_ip, false)
      proxy_protocol_v2    = coalesce(endpoint.proxy_protocol_v2, false)
      tags                 = endpoint.tags
      ## Plain targets and detailed targets, normalised; the key keeps plain targets at <endpoint>-<address>
      targets = concat(
        [for address in endpoint.targets : { key = address, ip = address, port = null, availability_zone = "all" }],
        [for target in endpoint.target_details : {
          key               = target.port == null ? target.ip : format("%s:%d", target.ip, target.port)
          ip                = target.ip
          port              = target.port
          availability_zone = target.availability_zone
        }],
      )
    } if local.enable_load_balancer && endpoint.type == "load-balancer" && length(endpoint.targets) + length(endpoint.target_details) > 0
  }
  ## The address ranges of the module subnets, which hold both the endpoints and the central load balancer
  load_balancer_cidr_blocks = sort(distinct(data.aws_subnet.load_balancer[*].cidr_block))
  ## One target group attachment per endpoint and target address (and port, when the target sets one)
  load_balancer_attachments = {
    for pair in flatten([
      for name, endpoint in local.load_balancer_endpoints : [
        for target in endpoint.targets : {
          availability_zone = target.availability_zone
          endpoint          = name
          key               = target.key
          port              = coalesce(target.port, endpoint.target_port)
          target            = target.ip
        }
      ]
    ]) : format("%s-%s", pair.endpoint, pair.key) => pair
  }
  ## The traffic and numeric health check ports the load balancer sends to, per target address
  load_balancer_flows = flatten([
    for name, endpoint in local.load_balancer_endpoints : [
      for target in endpoint.targets : [
        for port in distinct(compact([
          tostring(coalesce(target.port, endpoint.target_port)),
          endpoint.health_check.port == "traffic-port" ? "" : endpoint.health_check.port,
          ])) : {
          cidr     = format("%s/32", target.ip)
          endpoint = name
          port     = tonumber(port)
        }
      ]
    ]
  ])
  ## One egress rule per destination port, to every target address on it; a target shared by several endpoints is
  ## allowed once, as security groups reject duplicate rules
  load_balancer_egress_rules = {
    for port in distinct(local.load_balancer_flows[*].port) : tostring(port) => {
      cidr_blocks = sort(distinct([for flow in local.load_balancer_flows : flow.cidr if flow.port == port]))
      endpoints   = sort(distinct([for flow in local.load_balancer_flows : flow.endpoint if flow.port == port]))
      port        = port
    }
  }
  ## The rules of the load balancer security group as AWS counts them, one per address range
  load_balancer_rule_counts = {
    ingress = length(local.load_balancer_endpoints) * length(local.load_balancer_cidr_blocks)
    egress  = length(flatten([for rule in values(local.load_balancer_egress_rules) : rule.cidr_blocks]))
  }
}

## Provision the central internal network load balancer. Verified Access endpoints only reach load balancers and
## addresses in their own VPC, so services in spoke VPCs are reached through IP targets across the transit gateway
resource "aws_lb" "current" {
  count = local.enable_load_balancer ? 1 : 0

  enable_cross_zone_load_balancing = var.load_balancer.cross_zone_enabled
  enable_deletion_protection       = var.load_balancer.enable_deletion_protection
  internal                         = true
  load_balancer_type               = "network"
  name                             = local.resource_name
  security_groups                  = [aws_security_group.load_balancer[0].id]
  tags                             = merge(local.tags, { Name = local.resource_name })

  dynamic "subnet_mapping" {
    for_each = var.subnet_ids

    content {
      private_ipv4_address = lookup(var.load_balancer.private_ips, subnet_mapping.value, null)
      subnet_id            = subnet_mapping.value
    }
  }
}

## Provision the security group for the central load balancer, permitting traffic only from the module subnets on the
## listener ports and only to the registered targets on their target (and health check) ports. It allows the subnet
## ranges rather than the endpoint security groups, which would form a dependency cycle
resource "aws_security_group" "load_balancer" {
  count = local.enable_load_balancer ? 1 : 0

  description = format("Central load balancer for Verified Access %s", var.name)
  name        = format("%s-nlb", local.resource_name)
  tags        = merge(local.tags, { Name = format("%s-nlb", local.resource_name) })
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = local.load_balancer_endpoints

    content {
      cidr_blocks = local.load_balancer_cidr_blocks
      description = format("Verified Access endpoint %s", ingress.key)
      from_port   = ingress.value.listener_port
      protocol    = "tcp"
      to_port     = ingress.value.listener_port
    }
  }

  dynamic "egress" {
    for_each = local.load_balancer_egress_rules

    content {
      cidr_blocks = egress.value.cidr_blocks
      description = format("Targets of Verified Access endpoint%s %s", length(egress.value.endpoints) > 1 ? "s" : "", join(", ", egress.value.endpoints))
      from_port   = egress.value.port
      protocol    = "tcp"
      to_port     = egress.value.port
    }
  }

  lifecycle {
    ## Security groups hold a limited number of rules (one per address range), counted per direction
    precondition {
      condition = (
        local.load_balancer_rule_counts.ingress <= var.load_balancer.max_security_group_rules &&
        local.load_balancer_rule_counts.egress <= var.load_balancer.max_security_group_rules
      )
      error_message = format(
        "The central load balancer security group needs %d inbound rules (listeners x subnet ranges) and %d outbound rules (distinct target address and port pairs), over the limit of %d per direction. Target the tenants' own load balancers instead of individual hosts, spread endpoints over more deployments, or raise the rules per security group quota and set load_balancer.max_security_group_rules.",
        local.load_balancer_rule_counts.ingress,
        local.load_balancer_rule_counts.egress,
        var.load_balancer.max_security_group_rules,
      )
    }
  }
}

## Provision a target group per endpoint, with the service addresses as IP targets. Target group names are unique per
## account and region and at most 32 characters, so the name is <name_prefix>-<hash of name/endpoint>: unique per
## deployment, free of length rules, and within the <name_prefix>-* prefix pipeline roles are scoped to. The
## readable name is in the Name tag
resource "aws_lb_target_group" "current" {
  for_each = local.load_balancer_endpoints

  deregistration_delay = tostring(each.value.deregistration_delay)
  name                 = format("%s-%s", var.name_prefix, substr(sha1(format("%s/%s", var.name, each.key)), 0, local.target_group_hash_length))
  port                 = each.value.target_port
  preserve_client_ip   = tostring(each.value.preserve_client_ip)
  protocol             = "TCP"
  proxy_protocol_v2    = each.value.proxy_protocol_v2
  tags                 = merge(each.value.tags, { Name = format("%s-%s", local.resource_name, each.key) })
  target_type          = "ip"
  vpc_id               = var.vpc_id

  health_check {
    healthy_threshold   = each.value.health_check.healthy_threshold
    interval            = each.value.health_check.interval
    path                = each.value.health_check.protocol == "TCP" ? null : coalesce(each.value.health_check.path, "/")
    port                = each.value.health_check.port
    protocol            = each.value.health_check.protocol
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }
}

## Register the service addresses on their target ports; targets outside the load balancer VPC must use availability
## zone "all"
resource "aws_lb_target_group_attachment" "current" {
  for_each = local.load_balancer_attachments

  availability_zone = each.value.availability_zone
  port              = each.value.port
  target_group_arn  = aws_lb_target_group.current[each.value.endpoint].arn
  target_id         = each.value.target
}

## Provision a listener per endpoint on its listener port, forwarding to its target group
resource "aws_lb_listener" "current" {
  for_each = local.load_balancer_endpoints

  load_balancer_arn        = aws_lb.current[0].arn
  port                     = each.value.listener_port
  protocol                 = "TCP"
  tags                     = each.value.tags
  tcp_idle_timeout_seconds = var.load_balancer.tcp_idle_timeout_seconds

  default_action {
    target_group_arn = aws_lb_target_group.current[each.key].arn
    type             = "forward"
  }
}
