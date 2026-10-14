## Endpoint submodule tests: each endpoint type, its options and its least privilege security group.

mock_provider "aws" {}

variables {
  name       = "test-demo"
  group_id   = "vagr-0123456789abcdef0"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  tags = {
    "Environment" = "Testing"
  }
}

run "cidr_endpoint" {
  command = plan

  module {
    source = "./modules/endpoint"
  }

  variables {
    type        = "cidr"
    cidr        = "10.101.0.0/24"
    port_ranges = [{ from_port = 22, to_port = 22 }]
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.endpoint_type == "cidr"
    error_message = "The endpoint should be a cidr endpoint"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.cidr_options[0].cidr == "10.101.0.0/24"
    error_message = "The cidr options should target the CIDR"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.cidr_options[0].protocol == "tcp"
    error_message = "cidr endpoints are tcp only"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.endpoint_domain_prefix == "test-demo"
    error_message = "The endpoint domain prefix should default to the name"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.attachment_type == "vpc"
    error_message = "The endpoint should attach to the VPC"
  }

  assert {
    condition     = length(aws_security_group.current.egress) == 1
    error_message = "The security group should have exactly one egress rule"
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.current.egress : length(rule.cidr_blocks) == 1 && contains(rule.cidr_blocks, "10.101.0.0/24") && rule.from_port == 22 && rule.to_port == 22 && rule.protocol == "tcp"
    ])
    error_message = "A cidr endpoint may only send to its own CIDR on its own ports"
  }

  assert {
    condition     = length(aws_verifiedaccess_endpoint.current.load_balancer_options) == 0 && length(aws_verifiedaccess_endpoint.current.rds_options) == 0
    error_message = "Only the options for the endpoint type should be set"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.policy_document == null
    error_message = "No endpoint policy should be set unless supplied"
  }
}

run "https_load_balancer_endpoint" {
  command = plan

  module {
    source = "./modules/endpoint"
  }

  variables {
    type                   = "load-balancer"
    protocol               = "https"
    port                   = 443
    load_balancer_arn      = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/demo/abc"
    application_domain     = "demo.example.com"
    domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/abc"
    egress_cidr_blocks     = ["10.24.0.0/15"]
    policy_document        = "permit(principal, action, resource) when { context.crowdstrike.assessment.overall >= 50 };"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.load_balancer_options[0].port == 443
    error_message = "An https endpoint should use a single port"
  }

  assert {
    condition     = length(aws_verifiedaccess_endpoint.current.load_balancer_options[0].port_range) == 0
    error_message = "An https endpoint should not use port ranges"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.application_domain == "demo.example.com"
    error_message = "An https endpoint should set the application domain"
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.current.egress : length(rule.cidr_blocks) == 1 && contains(rule.cidr_blocks, "10.24.0.0/15") && rule.from_port == 443 && rule.to_port == 443
    ])
    error_message = "A load balancer endpoint should send to the egress CIDRs on its port"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.policy_document == "permit(principal, action, resource) when { context.crowdstrike.assessment.overall >= 50 };"
    error_message = "The supplied endpoint policy should be attached"
  }
}

run "tcp_load_balancer_endpoint" {
  command = plan

  module {
    source = "./modules/endpoint"
  }

  variables {
    type              = "load-balancer"
    protocol          = "tcp"
    port_ranges       = [{ from_port = 443, to_port = 443 }]
    load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/demo/abc"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.load_balancer_options[0].port == null
    error_message = "A tcp endpoint should use port ranges rather than a single port"
  }

  assert {
    condition     = length(aws_verifiedaccess_endpoint.current.load_balancer_options[0].port_range) == 1
    error_message = "A tcp endpoint should set its port range"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.application_domain == null
    error_message = "A tcp endpoint does not need an application domain"
  }
}

run "rds_endpoint" {
  command = plan

  module {
    source = "./modules/endpoint"
  }

  variables {
    type = "rds"
    port = 5432
    rds = {
      instance_arn = "arn:aws:rds:eu-west-2:111111111111:db:demo"
      endpoint     = "demo.abc.eu-west-2.rds.amazonaws.com"
    }
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.rds_options[0].rds_db_instance_arn == "arn:aws:rds:eu-west-2:111111111111:db:demo"
    error_message = "The rds options should target the instance"
  }

  assert {
    condition     = aws_verifiedaccess_endpoint.current.rds_options[0].port == 5432
    error_message = "The rds options should set the port"
  }

  assert {
    condition = anytrue([
      for rule in aws_security_group.current.egress : length(rule.cidr_blocks) == 1 && contains(rule.cidr_blocks, "10.0.0.0/8") && rule.from_port == 5432 && rule.to_port == 5432
    ])
    error_message = "An rds endpoint should send to the egress CIDRs on the database port"
  }
}

run "group_submodule" {
  command = plan

  module {
    source = "./modules/group"
  }

  variables {
    name            = "test-platform-engineers"
    instance_id     = "vai-0123456789abcdef0"
    policy_document = "permit(principal, action, resource) when { context.idc.groups has \"c242c5b0-6081-1845-6fa8-6e0d9513c107\" };"
    kms_key_arn     = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_verifiedaccess_group.current.policy_document == "permit(principal, action, resource) when { context.idc.groups has \"c242c5b0-6081-1845-6fa8-6e0d9513c107\" };"
    error_message = "The group should carry the rendered policy"
  }

  assert {
    condition     = aws_verifiedaccess_group.current.tags["Name"] == "test-platform-engineers"
    error_message = "The group should be named"
  }

  assert {
    condition     = aws_verifiedaccess_group.current.sse_configuration[0].kms_key_arn == "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The group should be encrypted with the supplied key"
  }
}
