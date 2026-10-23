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

  override_data {
    target = data.aws_vpc.current[0]
    values = {
      cidr_block = "10.10.0.0/16"
      cidr_block_associations = [
        { association_id = "vpc-cidr-assoc-0123456789abcdef0", cidr_block = "10.10.0.0/16", state = "associated" },
        { association_id = "vpc-cidr-assoc-0123456789abcdef1", cidr_block = "10.11.0.0/16", state = "associated" },
        { association_id = "vpc-cidr-assoc-0123456789abcdef2", cidr_block = "10.12.0.0/16", state = "disassociated" },
      ]
    }
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
    condition     = aws_lb_target_group.current["app-ssh"].name == format("verified-access-%s", substr(sha1("test/app-ssh/vpc-0123456789abcdef0/22"), 0, 16)) && aws_lb_target_group.current["app-ssh"].tags.Name == "verified-access-test-app-ssh" && aws_lb_target_group.current["app-ssh"].target_type == "ip"
    error_message = "The target group should be named verified-access-<hash of name/endpoint/vpc/target port>, tagged with the readable name, with IP targets"
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
    condition     = jsonencode(local.endpoint_targets["own-nlb"].egress_cidr_blocks) == jsonencode(["10.10.0.0/16", "10.11.0.0/16"]) && length(data.aws_vpc.current) == 1
    error_message = "An endpoint with its own load balancer should send to the address ranges associated with the VPC by default"
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

run "custom_name_prefix" {
  command = plan

  variables {
    name_prefix = "prod-euw2-va"
  }

  assert {
    condition     = aws_lb.current[0].name == "prod-euw2-va-test" && aws_security_group.load_balancer[0].name == "prod-euw2-va-test-nlb"
    error_message = "The load balancer and its security group should follow the name_prefix"
  }

  assert {
    condition     = startswith(aws_lb_target_group.current["app-ssh"].name, "prod-euw2-va-") && length(aws_lb_target_group.current["app-ssh"].name) <= 32 && aws_lb_target_group.current["app-ssh"].tags.Name == "prod-euw2-va-test-app-ssh"
    error_message = "The target group should be <name_prefix>-<hash>, at most 32 characters, tagged with the readable name"
  }

  assert {
    condition     = output.access_log_group_name == "/aws/prod-euw2-va/test"
    error_message = "The log group should follow the name_prefix"
  }
}

run "longest_name_prefix" {
  command = plan

  variables {
    name_prefix = "abcdefghij-klmnopqrst-u"
    name        = "test"
  }

  assert {
    condition     = length(aws_lb_target_group.current["app-ssh"].name) == 32
    error_message = "The target group hash should shrink so the name fits in 32 characters"
  }
}

run "invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Prod_VA-"
  }

  expect_failures = [var.name_prefix]
}

run "invalid_name_prefix_too_long_for_load_balancer" {
  command = plan

  variables {
    name_prefix = "abcdefghij-klmnopqrst-u"
    name        = "production"
  }

  expect_failures = [var.topology]
}

run "hub_shared_port_with_listener_ports" {
  command = apply

  variables {
    load_balancer = {
      cross_zone_enabled = false
    }
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["11111111-1111-1111-1111-111111111111"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the tenant services"
        }
        tags = {
          CostCentre = "platform"
        }
        endpoints = {
          ## Two SSH hosts on 22, on listener ports 2201 and 2202
          host-a-ssh = {
            type          = "load-balancer"
            port_ranges   = [{ from_port = 22, to_port = 22 }]
            targets       = ["10.50.0.10"]
            listener_port = 2201
            tags = {
              CostCentre = "tenant-a"
            }
          }
          host-b-ssh = {
            type                 = "load-balancer"
            port_ranges          = [{ from_port = 22, to_port = 22 }]
            listener_port        = 2202
            deregistration_delay = 30
            proxy_protocol_v2    = true
            target_details = [
              { ip = "10.50.0.11" },
              { ip = "10.50.0.12", port = 2222 },
              { ip = "10.10.0.50", availability_zone = "eu-west-2a" },
            ]
          }
          ## A web application on 80 with an HTTP health check on its own port, sharing a host with host-a-ssh
          app-web = {
            type                   = "load-balancer"
            protocol               = "http"
            port                   = 80
            application_domain     = "app.example.com"
            domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/00000000-0000-0000-0000-000000000000"
            targets                = ["10.50.0.10"]
            listener_port          = 8080
            health_check = {
              protocol = "HTTP"
              port     = "8081"
              path     = "/healthz"
              interval = 10
            }
          }
        }
      }
    }
  }

  assert {
    condition     = aws_lb.current[0].enable_cross_zone_load_balancing == false
    error_message = "Cross zone load balancing should be configurable"
  }

  assert {
    condition     = aws_lb_listener.current["host-a-ssh"].port == 2201 && aws_lb_listener.current["host-b-ssh"].port == 2202 && aws_lb_listener.current["app-web"].port == 8080
    error_message = "Each endpoint should have a listener on its listener port"
  }

  assert {
    condition     = aws_lb_target_group.current["host-a-ssh"].port == 22 && aws_lb_target_group.current["host-b-ssh"].port == 22 && aws_lb_target_group.current["app-web"].port == 80
    error_message = "The target groups should use the service port"
  }

  assert {
    condition = alltrue([
      local.endpoint_targets["host-a-ssh"].port_ranges[0].from_port == 2201,
      local.endpoint_targets["host-a-ssh"].port_ranges[0].to_port == 2201,
      local.endpoint_targets["app-web"].port == 8080,
    ])
    error_message = "The endpoints should connect to the load balancer on their listener port, the port clients use"
  }

  assert {
    condition = alltrue([
      aws_lb_target_group_attachment.current["host-a-ssh-10.50.0.10"].port == 22,
      aws_lb_target_group_attachment.current["host-b-ssh-10.50.0.11"].port == 22,
      aws_lb_target_group_attachment.current["host-b-ssh-10.50.0.12:2222"].port == 2222,
      aws_lb_target_group_attachment.current["host-b-ssh-10.50.0.11"].availability_zone == "all",
      aws_lb_target_group_attachment.current["host-b-ssh-10.10.0.50"].availability_zone == "eu-west-2a",
    ])
    error_message = "Targets should be registered on the service port unless they set their own, in their availability zone"
  }

  assert {
    condition = alltrue([
      aws_lb_target_group.current["app-web"].health_check[0].protocol == "HTTP",
      aws_lb_target_group.current["app-web"].health_check[0].port == "8081",
      aws_lb_target_group.current["app-web"].health_check[0].path == "/healthz",
      aws_lb_target_group.current["app-web"].health_check[0].interval == 10,
      aws_lb_target_group.current["host-a-ssh"].health_check[0].protocol == "TCP",
      aws_lb_target_group.current["host-a-ssh"].health_check[0].port == "traffic-port",
    ])
    error_message = "The health check should be configurable, defaulting to TCP on the traffic port"
  }

  assert {
    condition = alltrue([
      aws_lb_target_group.current["host-b-ssh"].deregistration_delay == "30",
      aws_lb_target_group.current["host-b-ssh"].proxy_protocol_v2 == true,
      aws_lb_target_group.current["host-a-ssh"].deregistration_delay == "300",
      aws_lb_target_group.current["host-a-ssh"].proxy_protocol_v2 == false,
      aws_lb_target_group.current["host-a-ssh"].preserve_client_ip == "false",
    ])
    error_message = "The target group settings should be configurable, defaulting to AWS's defaults for IP targets"
  }

  assert {
    condition = alltrue([
      for port in [2201, 2202, 8080] : anytrue([for rule in aws_security_group.load_balancer[0].ingress : rule.from_port == port])
    ]) && length(aws_security_group.load_balancer[0].ingress) == 3
    error_message = "The load balancer should accept each listener port from the module subnets"
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.load_balancer[0].egress : rule.from_port == 22 && toset(rule.cidr_blocks) == toset(["10.10.0.50/32", "10.50.0.10/32", "10.50.0.11/32"])
    ])
    error_message = "One egress rule should allow port 22 to every target on it"
  }

  assert {
    condition = alltrue([
      anytrue([for rule in aws_security_group.load_balancer[0].egress : rule.from_port == 2222 && toset(rule.cidr_blocks) == toset(["10.50.0.12/32"])]),
      anytrue([for rule in aws_security_group.load_balancer[0].egress : rule.from_port == 80 && toset(rule.cidr_blocks) == toset(["10.50.0.10/32"])]),
      anytrue([for rule in aws_security_group.load_balancer[0].egress : rule.from_port == 8081 && toset(rule.cidr_blocks) == toset(["10.50.0.10/32"])]),
    ]) && length(aws_security_group.load_balancer[0].egress) == 4
    error_message = "The load balancer should send to each target on its target port and numeric health check port"
  }

  assert {
    condition     = anytrue([for rule in aws_security_group.load_balancer[0].egress : rule.from_port == 22 && rule.description == "Targets of Verified Access endpoints host-a-ssh, host-b-ssh"])
    error_message = "A rule shared by several endpoints should name them all"
  }

  assert {
    condition = alltrue([
      aws_lb_target_group.current["host-a-ssh"].tags["CostCentre"] == "tenant-a",
      aws_lb_listener.current["host-a-ssh"].tags["CostCentre"] == "tenant-a",
      aws_lb_target_group.current["host-b-ssh"].tags["CostCentre"] == "platform",
      aws_lb_target_group.current["host-b-ssh"].tags["Environment"] == "Testing",
      !contains(keys(aws_lb.current[0].tags), "CostCentre"),
    ])
    error_message = "Endpoint tags should be merged over the group and module tags on its target group and listener only"
  }

  assert {
    condition     = output.target_group_arns["host-a-ssh"] == aws_lb_target_group.current["host-a-ssh"].arn && length(output.target_group_arns) == 3
    error_message = "The target group ARNs should be exported per endpoint with targets"
  }
}

run "hub_security_group_rule_quota" {
  command = plan

  variables {
    load_balancer = {
      max_security_group_rules = 2
    }
  }

  ## Two listeners from two subnet ranges are four inbound rules
  expect_failures = [aws_security_group.load_balancer]
}

run "hub_supplied_security_groups" {
  command = apply

  variables {
    load_balancer = {
      create_security_group = false
      security_group_ids    = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = length(aws_security_group.load_balancer) == 0
    error_message = "No load balancer security group should be created"
  }

  assert {
    condition     = tolist(aws_lb.current[0].security_groups) == tolist(["sg-0123456789abcdef0"])
    error_message = "The load balancer should use only the supplied security groups"
  }

  assert {
    condition     = output.load_balancer_security_group_id == null
    error_message = "No load balancer security group should be exported"
  }
}

run "hub_additional_security_groups" {
  command = apply

  variables {
    load_balancer = {
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = length(aws_lb.current[0].security_groups) == 2 && contains(aws_lb.current[0].security_groups, aws_security_group.load_balancer[0].id) && contains(aws_lb.current[0].security_groups, "sg-0123456789abcdef0")
    error_message = "The supplied security groups should be attached in addition to the created one"
  }
}

## allowed_egress_cidr_blocks overrides the VPC's address ranges, and the VPC is then not read

run "allowed_egress_cidr_blocks_override" {
  command = plan

  variables {
    allowed_egress_cidr_blocks = ["10.10.5.0/24"]
  }

  assert {
    condition     = jsonencode(local.endpoint_targets["own-nlb"].egress_cidr_blocks) == jsonencode(["10.10.5.0/24"]) && length(data.aws_vpc.current) == 0
    error_message = "allowed_egress_cidr_blocks should replace the VPC's address ranges without reading the VPC"
  }
}

## A target port change replaces the target group under a new name, created before the old one is destroyed, so the
## listener moves to it in place. The two applies share state, so the second plans the replacement

run "target_port_change_before" {
  command = apply
}

run "target_port_change_after" {
  command = apply

  variables {
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
            target_details = [
              { ip = "10.50.0.10", port = 2222 },
              { ip = "10.50.0.11", port = 2222 },
            ]
          }
          app-web = {
            type                   = "load-balancer"
            protocol               = "http"
            port                   = 8080
            listener_port          = 80
            application_domain     = "app.example.com"
            domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/00000000-0000-0000-0000-000000000000"
            targets                = ["10.50.0.20"]
          }
        }
      }
    }
  }

  assert {
    condition = (
      aws_lb_target_group.current["app-web"].name == format("verified-access-%s", substr(sha1("test/app-web/vpc-0123456789abcdef0/8080"), 0, 16)) &&
      aws_lb_target_group.current["app-web"].port == 8080 &&
      aws_lb_target_group.current["app-ssh"].name == format("verified-access-%s", substr(sha1("test/app-ssh/vpc-0123456789abcdef0/22"), 0, 16))
    )
    error_message = "A changed target port should name a new target group; an unchanged one (per target ports leave the target group port) keeps its name"
  }

  assert {
    condition     = aws_lb_listener.current["app-web"].port == 80 && aws_lb_listener.current["app-web"].default_action[0].target_group_arn == aws_lb_target_group.current["app-web"].arn
    error_message = "The listener should keep its port and forward to the new target group"
  }

  assert {
    condition     = aws_lb_target_group_attachment.current["app-ssh-10.50.0.10:2222"].port == 2222 && aws_lb_target_group_attachment.current["app-web-10.50.0.20"].port == 8080
    error_message = "The targets should be registered on their new ports"
  }
}
