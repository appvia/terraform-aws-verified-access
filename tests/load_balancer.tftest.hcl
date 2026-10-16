## Central load balancer tests: topology hub creates the load balancer, a listener and IP target group per endpoint
## with targets, and wires the endpoints to it; single-vpc creates none of it.

mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/verified-access-test/0123456789abcdef"
      arn_suffix = "net/verified-access-test/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/verified-access/0123456789abcdef"
    }
  }

  override_data {
    target = data.aws_subnet.load_balancer[0]
    values = { cidr_block = "10.10.0.0/24" }
  }

  override_data {
    target = data.aws_subnet.load_balancer[1]
    values = { cidr_block = "10.10.1.0/24" }
  }
}

variables {
  name       = "test"
  topology   = "hub"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

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

  groups = {
    platform-engineers = {
      policy = {
        identity_groups = ["11111111-1111-1111-1111-111111111111"]
        owner           = "platform-team"
        justification   = "Platform engineers operate the tenant services"
      }
      endpoints = {
        app-ssh = {
          type        = "load-balancer"
          port_ranges = [{ from_port = 22, to_port = 22 }]
          targets     = ["10.50.0.10", "10.50.0.11"]
        }
        app-web = {
          type                   = "load-balancer"
          protocol               = "http"
          port                   = 80
          application_domain     = "app.example.com"
          domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/00000000-0000-0000-0000-000000000000"
          targets                = ["10.50.0.20"]
        }
        own-nlb = {
          type              = "load-balancer"
          port_ranges       = [{ from_port = 5432, to_port = 5432 }]
          load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/tenant/abc"
        }
      }
    }
  }
}

run "hub_load_balancer" {
  command = apply

  assert {
    condition     = aws_lb.current[0].internal == true && aws_lb.current[0].load_balancer_type == "network"
    error_message = "The central load balancer should be an internal network load balancer"
  }

  assert {
    condition     = aws_lb.current[0].name == "verified-access-test" && aws_lb.current[0].enable_cross_zone_load_balancing == true
    error_message = "The central load balancer should be named verified-access-<name> with cross zone load balancing"
  }

  assert {
    condition     = aws_lb.current[0].enable_deletion_protection == false
    error_message = "Deletion protection should be off by default"
  }

  assert {
    condition     = length(aws_lb.current[0].subnet_mapping) == 2 && alltrue([for mapping in aws_lb.current[0].subnet_mapping : contains(var.subnet_ids, mapping.subnet_id)])
    error_message = "The central load balancer should sit in the module subnets"
  }

  assert {
    condition     = contains(aws_lb.current[0].security_groups, aws_security_group.load_balancer[0].id)
    error_message = "The central load balancer should use its own security group"
  }

  assert {
    condition     = aws_security_group.load_balancer[0].name == "verified-access-test-nlb"
    error_message = "The load balancer security group should be named verified-access-<name>-nlb"
  }

  assert {
    condition     = length(aws_security_group.load_balancer[0].ingress) == 2 && length(aws_security_group.load_balancer[0].egress) == 2
    error_message = "The load balancer security group should have one ingress and one egress rule per endpoint with targets"
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.load_balancer[0].ingress : rule.from_port == 22 && rule.to_port == 22 && length(rule.cidr_blocks) == 2 && contains(rule.cidr_blocks, "10.10.0.0/24") && contains(rule.cidr_blocks, "10.10.1.0/24")
    ])
    error_message = "The load balancer should accept the endpoint port only from the module subnets"
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.load_balancer[0].egress : rule.from_port == 22 && rule.to_port == 22 && length(rule.cidr_blocks) == 2 && contains(rule.cidr_blocks, "10.50.0.10/32") && contains(rule.cidr_blocks, "10.50.0.11/32")
    ])
    error_message = "The load balancer should send the endpoint port only to its targets"
  }

  assert {
    condition     = length(aws_lb_target_group.current) == 2 && length(aws_lb_listener.current) == 2
    error_message = "One target group and listener should be created per endpoint with targets"
  }

  assert {
    condition     = aws_lb_target_group.current["app-ssh"].name == "va-test-app-ssh" && aws_lb_target_group.current["app-ssh"].target_type == "ip"
    error_message = "The target group should be named va-<name>-<endpoint> with IP targets"
  }

  assert {
    condition     = aws_lb_target_group.current["app-web"].port == 80 && aws_lb_target_group.current["app-web"].protocol == "TCP"
    error_message = "An http endpoint should use its port on a TCP target group"
  }

  assert {
    condition     = aws_lb_target_group.current["app-ssh"].health_check[0].protocol == "TCP"
    error_message = "The target group should use TCP health checks"
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.current) == 3 && alltrue([for attachment in aws_lb_target_group_attachment.current : attachment.availability_zone == "all"])
    error_message = "Each target should be attached with availability zone all, as it is outside the load balancer VPC"
  }

  assert {
    condition     = aws_lb_target_group_attachment.current["app-ssh-10.50.0.11"].target_id == "10.50.0.11" && aws_lb_target_group_attachment.current["app-ssh-10.50.0.11"].port == 22
    error_message = "Each target should be attached on the endpoint port"
  }

  assert {
    condition     = aws_lb_listener.current["app-ssh"].port == 22 && aws_lb_listener.current["app-ssh"].protocol == "TCP"
    error_message = "A tcp endpoint should have a TCP listener on its single port"
  }

  assert {
    condition     = aws_lb_listener.current["app-web"].tcp_idle_timeout_seconds == 350
    error_message = "The listener idle timeout should default to 350 seconds"
  }

  assert {
    condition     = aws_lb_listener.current["app-web"].default_action[0].target_group_arn == aws_lb_target_group.current["app-web"].arn
    error_message = "The listener should forward to the endpoint's target group"
  }

  assert {
    condition     = local.endpoint_targets["app-ssh"].load_balancer_arn == aws_lb.current[0].arn
    error_message = "An endpoint with targets should use the central load balancer"
  }

  assert {
    condition     = length(local.endpoint_targets["app-ssh"].egress_cidr_blocks) == 2 && contains(local.endpoint_targets["app-ssh"].egress_cidr_blocks, "10.10.0.0/24") && contains(local.endpoint_targets["app-ssh"].egress_cidr_blocks, "10.10.1.0/24")
    error_message = "An endpoint with targets should only send to the module subnets, which hold the load balancer"
  }

  assert {
    condition     = local.endpoint_targets["own-nlb"].load_balancer_arn == "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/tenant/abc"
    error_message = "An endpoint with its own load balancer should keep it"
  }

  assert {
    condition     = length(local.endpoint_targets["own-nlb"].egress_cidr_blocks) == 1 && contains(local.endpoint_targets["own-nlb"].egress_cidr_blocks, "10.0.0.0/8")
    error_message = "An endpoint with its own load balancer should keep the allowed egress CIDR blocks"
  }

  assert {
    condition     = output.load_balancer_arn == aws_lb.current[0].arn && output.load_balancer_dns_name == aws_lb.current[0].dns_name
    error_message = "The load balancer should be exported"
  }

  assert {
    condition     = output.load_balancer_security_group_id == aws_security_group.load_balancer[0].id
    error_message = "The load balancer security group should be exported"
  }
}

run "hub_settings" {
  command = plan

  variables {
    load_balancer = {
      enable_deletion_protection = true
      tcp_idle_timeout_seconds   = 1800
      private_ips = {
        "subnet-0123456789abcdef0" = "10.10.0.100"
        "subnet-0123456789abcdef1" = "10.10.1.100"
      }
    }
  }

  assert {
    condition     = aws_lb.current[0].enable_deletion_protection == true
    error_message = "Deletion protection should be configurable"
  }

  assert {
    condition = alltrue([
      for mapping in aws_lb.current[0].subnet_mapping : mapping.private_ipv4_address == var.load_balancer.private_ips[mapping.subnet_id]
    ])
    error_message = "The load balancer should use the fixed private address in each subnet"
  }

  assert {
    condition     = aws_lb_listener.current["app-ssh"].tcp_idle_timeout_seconds == 1800
    error_message = "The listener idle timeout should be configurable"
  }
}

run "hub_partial_private_ips" {
  command = plan

  variables {
    load_balancer = {
      private_ips = {
        "subnet-0123456789abcdef1" = "10.10.1.100"
      }
    }
  }

  assert {
    condition = anytrue([
      for mapping in aws_lb.current[0].subnet_mapping : mapping.subnet_id == "subnet-0123456789abcdef0" && mapping.private_ipv4_address == null
    ])
    error_message = "A subnet without a fixed address should let AWS assign one"
  }
}

run "hub_without_targets" {
  command = plan

  variables {
    groups = {}
  }

  assert {
    condition     = length(aws_lb.current) == 1
    error_message = "The central load balancer should be created with topology hub even without endpoints"
  }

  assert {
    condition     = length(aws_lb_listener.current) == 0 && length(aws_lb_target_group.current) == 0 && length(aws_lb_target_group_attachment.current) == 0
    error_message = "No listeners or target groups should be created without endpoints with targets"
  }

  assert {
    condition     = length(aws_security_group.load_balancer) == 1 && length(local.load_balancer_endpoints) == 0
    error_message = "The load balancer security group should be created with no endpoint rules"
  }
}

run "single_vpc" {
  command = plan

  variables {
    topology = "single-vpc"
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["11111111-1111-1111-1111-111111111111"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the tenant services"
        }
        endpoints = {
          own-nlb = {
            type              = "load-balancer"
            port_ranges       = [{ from_port = 5432, to_port = 5432 }]
            load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/tenant/abc"
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_lb.current) == 0 && length(aws_security_group.load_balancer) == 0 && length(data.aws_subnet.load_balancer) == 0
    error_message = "No central load balancer should be created with topology single-vpc"
  }

  assert {
    condition     = output.load_balancer_arn == null && output.load_balancer_dns_name == null && output.load_balancer_security_group_id == null
    error_message = "The load balancer outputs should be null with topology single-vpc"
  }

  assert {
    condition     = local.endpoint_targets["own-nlb"].load_balancer_arn == "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/tenant/abc"
    error_message = "A load-balancer endpoint should use its own load balancer with topology single-vpc"
  }
}
