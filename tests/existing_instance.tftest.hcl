## Existing instance tests: with existing_instance the module adds groups and endpoints (and, with topology hub, the
## central load balancer) to an instance owned elsewhere, creating no instance, trust providers or logging, and renders
## the policies exactly as for the trust providers it would create (the same golden files).

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-2"
    }
  }

  override_data {
    target = data.aws_subnet.load_balancer[0]
    values = { cidr_block = "10.10.0.0/24" }
  }
}

variables {
  name       = "test"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0"]

  tags = {
    "Environment" = "Testing"
    "GitRepo"     = "https://github.com/appvia/terraform-aws-verified-access"
  }

  existing_instance = {
    id                         = "vai-0123456789abcdef0"
    user_policy_reference_name = "idc"
    device_trust_provider = {
      type = "crowdstrike"
    }
  }

  groups = {
    platform-engineers = {
      policy = {
        identity_groups = ["d242c5b0-6081-1845-6fa8-6e0d9513c107", "11111111-1111-1111-1111-111111111111", "11111111-1111-1111-1111-111111111111"]
        owner           = "platform-team"
        justification   = "Platform engineers operate the demo tenant hosts"
      }
      endpoints = {
        demo-ssh = {
          type        = "cidr"
          cidr        = "10.101.0.0/24"
          port_ranges = [{ from_port = 22, to_port = 22 }]
          sensitive   = true
        }
      }
    }
  }
}

run "existing_instance" {
  command = apply

  assert {
    condition = (
      length(aws_verifiedaccess_instance.current) == 0 &&
      length(aws_verifiedaccess_trust_provider.user) == 0 &&
      length(aws_verifiedaccess_trust_provider.device) == 0 &&
      length(aws_verifiedaccess_instance_trust_provider_attachment.user) == 0 &&
      length(aws_verifiedaccess_instance_trust_provider_attachment.device) == 0
    )
    error_message = "No instance, trust provider or attachment should be created for an existing instance"
  }

  assert {
    condition     = length(aws_verifiedaccess_instance_logging_configuration.current) == 0 && length(aws_wafv2_web_acl_association.current) == 0
    error_message = "The existing instance's logging and web ACL are owned elsewhere"
  }

  assert {
    condition     = module.groups["platform-engineers"].id != null && length(module.endpoints) == 1
    error_message = "The groups and endpoints should be created"
  }

  assert {
    condition = alltrue([
      output.instance_id == "vai-0123456789abcdef0",
      output.instance_arn == "arn:aws:ec2:eu-west-2:111111111111:verified-access-instance/vai-0123456789abcdef0",
      output.user_trust_provider_id == null,
      output.device_trust_provider_id == null,
      length(output.name_servers) == 0,
      strcontains(output.client_configuration_command, "--verified-access-instance-id vai-0123456789abcdef0"),
    ])
    error_message = "The outputs should describe the existing instance"
  }
}

run "existing_instance_verified_email" {
  command = plan

  variables {
    existing_instance = {
      id                         = "vai-0123456789abcdef0"
      user_policy_reference_name = "idc"
      require_verified_email     = true
      device_trust_provider = {
        type = "crowdstrike"
      }
    }
  }

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-identity-center-verified-email.cedar")
    error_message = "The group policy should require a verified email as for a created provider (tests/golden/group-identity-center-verified-email.cedar)"
  }
}

run "existing_instance_identity_center_policies" {
  command = plan

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-identity-center.cedar")
    error_message = "The group policy should render as for a created Identity Center provider (tests/golden/group-identity-center.cedar)"
  }

  assert {
    condition     = output.rendered_policies["endpoint/demo-ssh"] == file("./tests/golden/endpoint-crowdstrike.cedar")
    error_message = "The sensitive endpoint policy should render as for a created CrowdStrike provider (tests/golden/endpoint-crowdstrike.cedar)"
  }
}

run "existing_instance_oidc_policies" {
  command = plan

  variables {
    existing_instance = {
      id                         = "vai-0123456789abcdef0"
      user_trust_provider_type   = "oidc"
      user_policy_reference_name = "okta"
      device_trust_provider = {
        type = "crowdstrike"
      }
    }
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["platform-engineers", "admins"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
      }
    }
  }

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-oidc.cedar")
    error_message = "The group policy should render as for a created OIDC provider (tests/golden/group-oidc.cedar)"
  }
}

run "existing_instance_groups_claim" {
  command = plan

  variables {
    existing_instance = {
      id                         = "vai-0123456789abcdef0"
      user_trust_provider_type   = "oidc"
      user_policy_reference_name = "okta"
      user_groups_claim          = "additional_user_context.groups"
    }
    groups = {
      engineers = {
        policy = {
          identity_groups = ["engineers"]
          owner           = "platform-team"
          justification   = "Engineers reach internal tooling"
        }
      }
    }
  }

  assert {
    condition     = strcontains(output.rendered_policies["group/engineers"], "context.okta.additional_user_context.groups.contains(\"engineers\")")
    error_message = "The configured groups claim should be rendered"
  }

  assert {
    condition     = !strcontains(output.rendered_policies["group/engineers"], "device-context")
    error_message = "Without an attached device provider no device context should be rendered"
  }
}

run "existing_instance_hub" {
  command = plan

  variables {
    topology = "hub"
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
            targets     = ["10.50.0.10"]
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_lb.current) == 1 && length(aws_lb_listener.current) == 1 && length(aws_verifiedaccess_instance.current) == 0
    error_message = "The central load balancer should be created for an existing instance"
  }
}

run "existing_instance_sensitive_without_device_provider" {
  command = plan

  variables {
    existing_instance = {
      id                         = "vai-0123456789abcdef0"
      user_policy_reference_name = "idc"
    }
  }

  expect_failures = [var.groups]
}
