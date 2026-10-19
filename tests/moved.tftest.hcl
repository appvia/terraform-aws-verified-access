## Moved block tests: a deployment made before the instance, the user trust provider, its attachment and the endpoint
## security group were created with count keeps them when upgrading. The first run applies their old addresses
## (tests/fixtures/before-count); the second applies the module to the same state (state_key), and each must reach its
## [0] address with the same id rather than being destroyed and recreated. Terraform also moves an address to [0]
## implicitly when count is added, so this proves the upgrade path rather than each moved block on its own: removing a
## moved block still passes, while losing the address (e.g. a renamed endpoint key) fails. The run block state_key
## needs a newer Terraform than the module's minimum (1.9) to run this test.

mock_provider "aws" {}

variables {
  name       = "test"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0"]

  tags = {
    "Environment" = "Testing"
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
        justification   = "Platform engineers operate the demo tenant hosts"
      }
      endpoints = {
        demo-ssh = {
          type        = "cidr"
          cidr        = "10.101.0.0/24"
          port_ranges = [{ from_port = 22, to_port = 22 }]
        }
      }
    }
  }
}

run "before_count" {
  command   = apply
  state_key = "upgrade"

  module {
    source = "./tests/fixtures/before-count"
  }
}

run "after_count" {
  command   = apply
  state_key = "upgrade"

  assert {
    condition = (
      aws_verifiedaccess_instance.current[0].id == run.before_count.instance_id &&
      aws_verifiedaccess_trust_provider.user[0].id == run.before_count.user_trust_provider_id &&
      aws_verifiedaccess_instance_trust_provider_attachment.user[0].id == run.before_count.user_attachment_id
    )
    error_message = "The instance, user trust provider and attachment should be moved to [0], keeping their ids"
  }

  assert {
    condition     = output.endpoint_security_group_ids["demo-ssh"] == run.before_count.endpoint_security_group_id
    error_message = "The endpoint security group should be moved to [0] in the endpoint module, keeping its id"
  }
}
