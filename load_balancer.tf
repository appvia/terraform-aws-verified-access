locals {
  ## Indicates the central load balancer is created (topology hub)
  enable_load_balancer = var.topology == "hub"
  ## The endpoints reaching services across the transit gateway through the central load balancer, with their listener
  ## port: the port of http and https endpoints, the single port range of tcp endpoints
  load_balancer_endpoints = {
    for name, endpoint in local.endpoints : name => {
      port    = endpoint.protocol == "tcp" ? endpoint.port_ranges[0].from_port : endpoint.port
      targets = endpoint.targets
    } if local.enable_load_balancer && endpoint.type == "load-balancer" && length(endpoint.targets) > 0
  }
  ## The address ranges of the module subnets, which hold both the endpoints and the central load balancer
  load_balancer_cidr_blocks = sort(distinct(data.aws_subnet.load_balancer[*].cidr_block))
  ## One target group attachment per endpoint and target address
  load_balancer_attachments = {
    for pair in flatten([
      for name, endpoint in local.load_balancer_endpoints : [
        for target in endpoint.targets : { endpoint = name, port = endpoint.port, target = target }
      ]
    ]) : format("%s-%s", pair.endpoint, pair.target) => pair
  }
}

## Provision the central internal network load balancer. Verified Access endpoints only reach load balancers and
## addresses in their own VPC, so services in spoke VPCs are reached through IP targets across the transit gateway
resource "aws_lb" "current" {
  count = local.enable_load_balancer ? 1 : 0

  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.load_balancer.enable_deletion_protection
  internal                         = true
  load_balancer_type               = "network"
  name                             = format("verified-access-%s", var.name)
  security_groups                  = [aws_security_group.load_balancer[0].id]
  tags                             = merge(local.tags, { Name = format("verified-access-%s", var.name) })

  dynamic "subnet_mapping" {
    for_each = var.subnet_ids

    content {
      private_ipv4_address = lookup(var.load_balancer.private_ips, subnet_mapping.value, null)
      subnet_id            = subnet_mapping.value
    }
  }
}

## Provision the security group for the central load balancer, permitting traffic only from the module subnets and
## only to the registered targets. It allows the subnet ranges rather than the endpoint security groups, which would
## form a dependency cycle
resource "aws_security_group" "load_balancer" {
  count = local.enable_load_balancer ? 1 : 0

  description = format("Central load balancer for Verified Access %s", var.name)
  name        = format("verified-access-%s-nlb", var.name)
  tags        = merge(local.tags, { Name = format("verified-access-%s-nlb", var.name) })
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = local.load_balancer_endpoints

    content {
      cidr_blocks = local.load_balancer_cidr_blocks
      description = format("Verified Access endpoint %s", ingress.key)
      from_port   = ingress.value.port
      protocol    = "tcp"
      to_port     = ingress.value.port
    }
  }

  dynamic "egress" {
    for_each = local.load_balancer_endpoints

    content {
      cidr_blocks = [for target in egress.value.targets : format("%s/32", target)]
      description = format("Targets of Verified Access endpoint %s", egress.key)
      from_port   = egress.value.port
      protocol    = "tcp"
      to_port     = egress.value.port
    }
  }
}

## Provision a target group per endpoint, with the service addresses as IP targets; target group names are unique per
## account and region, so the name includes the deployment to let several deployments share an account
resource "aws_lb_target_group" "current" {
  for_each = local.load_balancer_endpoints

  name        = format("va-%s-%s", var.name, each.key)
  port        = each.value.port
  protocol    = "TCP"
  tags        = merge(local.tags, { Name = format("va-%s-%s", var.name, each.key) })
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "TCP"
  }
}

## Register the service addresses; targets outside the load balancer VPC must use availability zone "all"
resource "aws_lb_target_group_attachment" "current" {
  for_each = local.load_balancer_attachments

  availability_zone = "all"
  port              = each.value.port
  target_group_arn  = aws_lb_target_group.current[each.value.endpoint].arn
  target_id         = each.value.target
}

## Provision a listener per endpoint, forwarding its port to its target group
resource "aws_lb_listener" "current" {
  for_each = local.load_balancer_endpoints

  load_balancer_arn        = aws_lb.current[0].arn
  port                     = each.value.port
  protocol                 = "TCP"
  tags                     = local.tags
  tcp_idle_timeout_seconds = var.load_balancer.tcp_idle_timeout_seconds

  default_action {
    target_group_arn = aws_lb_target_group.current[each.key].arn
    type             = "forward"
  }
}
