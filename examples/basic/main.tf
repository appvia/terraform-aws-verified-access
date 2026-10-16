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

## Provision a VPC with private subnets for the workload and dedicated subnets for Verified Access
module "network" {
  source  = "appvia/network/aws"
  version = "0.7.0"

  availability_zones     = 2
  name                   = "verified-access-basic"
  private_subnet_netmask = 24
  tags                   = local.tags
  vpc_cidr               = "10.10.0.0/21"

  subnets = {
    verified_access = {
      netmask = 27
    }
  }
}

## Permit SSH to the target only from the dedicated Verified Access subnets
resource "aws_security_group" "target" {
  name        = "verified-access-basic-target"
  description = "Permit SSH from the Verified Access endpoint subnets only"
  tags        = local.tags
  vpc_id      = module.network.vpc_id

  ingress {
    cidr_blocks = module.network.all_subnets_by_name["verified_access"].cidr_blocks
    description = "SSH from Verified Access"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }
}

## Provision a private Linux host to reach over SSH, standing in for a server behind a bastion today
resource "aws_instance" "target" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = module.network.private_subnet_ids[0]
  tags                   = merge(local.tags, { Name = "verified-access-basic-target" })
  vpc_security_group_ids = [aws_security_group.target.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }
}

## Provision Verified Access with IAM Identity Center and an SSH endpoint to the target in the same VPC
module "verified_access" {
  source = "../.."

  name       = "basic"
  subnet_ids = module.network.all_subnets_by_name["verified_access"].ids
  tags       = local.tags
  topology   = "single-vpc"
  vpc_id     = module.network.vpc_id

  user_trust_provider = {
    type = "iam-identity-center"
  }

  access_logs = {
    include_trust_context = true
    cloudwatch            = {}
  }

  groups = {
    engineers = {
      description = "Engineers permitted to reach the demonstration target"
      policy = {
        identity_groups = var.identity_group_ids
        owner           = "platform-team"
        justification   = "Engineers administer the demonstration target over SSH"
      }
      endpoints = {
        target-ssh = {
          type        = "cidr"
          cidr        = format("%s/32", aws_instance.target.private_ip)
          port_ranges = [{ from_port = 22, to_port = 22 }]
        }
      }
    }
  }
}
