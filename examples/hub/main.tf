#####################################################################################
# Terraform module examples are meant to show an _example_ on how to use a module
# per use-case. The code below should not be copied directly but referenced in order
# to build your own root module that invokes this module
#####################################################################################

locals {
  ## The tags applied to all resources
  tags = {
    "Environment" = "Testing"
    "GitRepo"     = "https://github.com/appvia/terraform-aws-verified-access"
  }
  ## The spoke subnet holding the targets (the first private subnet of 10.50.0.0/21)
  target_subnet_cidr = "10.50.0.0/24"
  ## The fixed private addresses of the two SSH targets; load balancer targets must be known at plan time
  target_private_ips = {
    a = cidrhost(local.target_subnet_cidr, 10)
    b = cidrhost(local.target_subnet_cidr, 11)
  }
}

## Find the latest Amazon Linux 2023 image for the demonstration target
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

## Provision the transit gateway connecting the hub and spoke VPCs
resource "aws_ec2_transit_gateway" "current" {
  description = "Verified Access hub and spoke example"
  tags        = merge(local.tags, { Name = "verified-access-hub" })
}

## Provision the hub VPC with dedicated subnets for the Verified Access endpoints and the central load balancer, routing
## to the spokes through the transit gateway
module "hub" {
  source  = "appvia/network/aws"
  version = "0.7.0"

  availability_zones     = 2
  name                   = "verified-access-hub"
  private_subnet_netmask = 24
  tags                   = local.tags
  transit_gateway_id     = aws_ec2_transit_gateway.current.id
  vpc_cidr               = "10.10.0.0/21"

  subnets = {
    verified_access = {
      netmask = 27
    }
  }

  transit_gateway_routes = {
    private         = "10.0.0.0/8"
    verified_access = "10.0.0.0/8"
  }
}

## Provision the spoke VPC holding the tenant service, attached to the same transit gateway
module "spoke" {
  source  = "appvia/network/aws"
  version = "0.7.0"

  availability_zones     = 2
  name                   = "verified-access-spoke"
  private_subnet_netmask = 24
  tags                   = local.tags
  transit_gateway_id     = aws_ec2_transit_gateway.current.id
  vpc_cidr               = "10.50.0.0/21"
}

## Permit SSH to the target only from the hub subnets holding the endpoints and the central load balancer
resource "aws_security_group" "target" {
  name        = "verified-access-hub-target"
  description = "Permit SSH from the Verified Access subnets in the hub only"
  tags        = local.tags
  vpc_id      = module.spoke.vpc_id

  ingress {
    cidr_blocks = module.hub.all_subnets_by_name["verified_access"].cidr_blocks
    description = "SSH from Verified Access"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
}

## Provision two private Linux hosts in the spoke VPC to reach over SSH, in the private subnet holding their fixed
## addresses; both listen on 22
resource "aws_instance" "target" {
  for_each = local.target_private_ips

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  private_ip             = each.value
  subnet_id              = one([for id, cidr in module.spoke.private_subnet_cidr_by_id : id if cidr == local.target_subnet_cidr])
  tags                   = merge(local.tags, { Name = format("verified-access-hub-target-%s", each.key) })
  vpc_security_group_ids = [aws_security_group.target.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }
}

## Provision Verified Access in the hub, reaching the target across the transit gateway through the central load
## balancer, with alarms and a dashboard
module "verified_access" {
  source = "../.."

  name       = "hub"
  subnet_ids = module.hub.all_subnets_by_name["verified_access"].ids
  tags       = local.tags
  topology   = "hub"
  vpc_id     = module.hub.vpc_id

  user_trust_provider = {
    type = "iam-identity-center"
  }

  access_logs = {
    include_trust_context = true
    cloudwatch            = {}
  }

  alarms = {
    email_addresses = var.alarm_email_addresses
  }

  dashboard = {}

  ## Uncomment to serve http endpoints on <app>.example.com with a certificate requested by the module; publish the
  ## certificate_validation_records output in the example.com zone
  # certificate = {
  #   domain_name = "example.com"
  # }

  ## Uncomment, with the certificate, to let the module publish the certificate validation records and the
  ## application CNAMEs in a Route 53 public hosted zone for example.com
  # dns = {
  #   zone_id = "Z0123456789ABCDEFGHIJ"
  # }

  groups = {
    engineers = {
      description = "Engineers permitted to reach the demonstration target"
      policy = {
        identity_groups = var.identity_group_ids
        owner           = "platform-team"
        justification   = "Engineers administer the demonstration target over SSH"
      }
      ## Both hosts listen on 22, so each has its own listener port on the central load balancer, which is also the
      ## port users connect to: ssh -p 2201 ec2-user@<target-a-ssh endpoint domain>
      endpoints = {
        target-a-ssh = {
          type          = "load-balancer"
          port_ranges   = [{ from_port = 22, to_port = 22 }]
          targets       = [local.target_private_ips["a"]]
          listener_port = 2201
        }
        target-b-ssh = {
          type          = "load-balancer"
          port_ranges   = [{ from_port = 22, to_port = 22 }]
          targets       = [local.target_private_ips["b"]]
          listener_port = 2202
        }
      }
    }
  }
}
