## Module wiring tests: the instance, trust providers, attachments, groups and endpoints.

mock_provider "aws" {}

variables {
  name       = "test"
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
        justification   = "Platform engineers operate the demo tenant hosts"
      }
      endpoints = {
        demo-ssh = {
          type        = "cidr"
          cidr        = "10.101.0.0/24"
          port_ranges = [{ from_port = 22, to_port = 22 }]
        }
        demo-db = {
          type = "rds"
          port = 5432
          rds = {
            instance_arn = "arn:aws:rds:eu-west-2:111111111111:db:demo"
            endpoint     = "demo.abc.eu-west-2.rds.amazonaws.com"
          }
        }
      }
    }
  }
}

run "identity_center" {
  command = apply

  assert {
    condition     = aws_verifiedaccess_instance.current.tags["Name"] == "test"
    error_message = "The instance should be named after var.name"
  }

  assert {
    condition     = aws_verifiedaccess_instance.current.tags["Environment"] == "Testing"
    error_message = "The instance should carry the supplied tags"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.trust_provider_type == "user"
    error_message = "The user trust provider should be a user provider"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.user_trust_provider_type == "iam-identity-center"
    error_message = "The user trust provider should use IAM Identity Center"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.policy_reference_name == "idc"
    error_message = "The user trust provider should use the same context key as the rendered policies"
  }

  assert {
    condition     = length(aws_verifiedaccess_trust_provider.user.oidc_options) == 0
    error_message = "No OIDC options should be set for IAM Identity Center"
  }

  assert {
    condition     = length(aws_verifiedaccess_trust_provider.device) == 0 && length(aws_verifiedaccess_instance_trust_provider_attachment.device) == 0
    error_message = "No device provider should be created unless configured"
  }

  assert {
    condition     = aws_verifiedaccess_instance_trust_provider_attachment.user.verifiedaccess_trust_provider_id == aws_verifiedaccess_trust_provider.user.id
    error_message = "The user trust provider should be attached to the instance"
  }

  assert {
    condition     = keys(output.group_ids) == ["platform-engineers"]
    error_message = "One group should be created"
  }

  assert {
    condition     = toset(keys(output.endpoint_ids)) == toset(["demo-db", "demo-ssh"])
    error_message = "Both endpoints should be created"
  }

  assert {
    condition     = output.instance_id == aws_verifiedaccess_instance.current.id
    error_message = "The instance id should be exported"
  }
}

run "device_trust_provider" {
  command = apply

  variables {
    device_trust_provider = {
      type      = "jamf"
      tenant_id = "tenant"
    }
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.device[0].device_trust_provider_type == "jamf"
    error_message = "The device trust provider should use the configured type"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.device[0].policy_reference_name == "jamf"
    error_message = "The device context key should default to the provider type"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.device[0].device_options[0].tenant_id == "tenant"
    error_message = "The device trust provider should use the configured tenant"
  }

  assert {
    condition     = aws_verifiedaccess_instance_trust_provider_attachment.device[0].verifiedaccess_trust_provider_id == aws_verifiedaccess_trust_provider.device[0].id
    error_message = "The device trust provider should be attached to the instance"
  }

  assert {
    condition     = output.device_trust_provider_id == aws_verifiedaccess_trust_provider.device[0].id
    error_message = "The device trust provider id should be exported"
  }
}

run "oidc_with_native_application" {
  command = apply

  variables {
    oidc_client_secret = "not-a-real-secret"
    user_trust_provider = {
      type                  = "oidc"
      policy_reference_name = "okta"
      oidc = {
        issuer                      = "https://example.okta.com"
        authorization_endpoint      = "https://example.okta.com/oauth2/v1/authorize"
        token_endpoint              = "https://example.okta.com/oauth2/v1/token"
        user_info_endpoint          = "https://example.okta.com/oauth2/v1/userinfo"
        client_id                   = "client"
        public_signing_key_endpoint = "https://example.okta.com/oauth2/v1/keys"
      }
    }
    groups = {}
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.user_trust_provider_type == "oidc"
    error_message = "The user trust provider should use OIDC"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.oidc_options[0].client_id == "client"
    error_message = "The OIDC options should be set"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.oidc_options[0].scope == "openid email groups offline_access"
    error_message = "The OIDC scope should default to include offline_access"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.native_application_oidc_options[0].public_signing_key_endpoint == "https://example.okta.com/oauth2/v1/keys"
    error_message = "The native application options should be set for Connectivity Client access"
  }
}

run "customer_managed_key" {
  command = apply

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user.sse_specification[0].kms_key_arn == "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The trust provider should be encrypted with the supplied key"
  }
}
