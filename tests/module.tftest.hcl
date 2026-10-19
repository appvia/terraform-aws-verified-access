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
    condition     = aws_verifiedaccess_instance.current[0].tags["Name"] == "verified-access-test"
    error_message = "The instance should be tagged <name_prefix>-<name>"
  }

  assert {
    condition     = aws_verifiedaccess_instance.current[0].tags["Environment"] == "Testing"
    error_message = "The instance should carry the supplied tags"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user[0].trust_provider_type == "user"
    error_message = "The user trust provider should be a user provider"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user[0].user_trust_provider_type == "iam-identity-center"
    error_message = "The user trust provider should use IAM Identity Center"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user[0].policy_reference_name == "idc"
    error_message = "The user trust provider should use the same context key as the rendered policies"
  }

  assert {
    condition     = length(aws_verifiedaccess_trust_provider.user[0].oidc_options) == 0
    error_message = "No OIDC options should be set for IAM Identity Center"
  }

  assert {
    condition     = length(aws_verifiedaccess_trust_provider.device) == 0 && length(aws_verifiedaccess_instance_trust_provider_attachment.device) == 0
    error_message = "No device provider should be created unless configured"
  }

  assert {
    condition     = aws_verifiedaccess_instance_trust_provider_attachment.user[0].verifiedaccess_trust_provider_id == aws_verifiedaccess_trust_provider.user[0].id
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
    condition     = output.instance_id == aws_verifiedaccess_instance.current[0].id
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
    condition     = aws_verifiedaccess_trust_provider.user[0].user_trust_provider_type == "oidc"
    error_message = "The user trust provider should use OIDC"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user[0].oidc_options[0].client_id == "client"
    error_message = "The OIDC options should be set"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user[0].oidc_options[0].scope == "openid email groups offline_access"
    error_message = "The OIDC scope should default to include offline_access"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user[0].native_application_oidc_options[0].public_signing_key_endpoint == "https://example.okta.com/oauth2/v1/keys"
    error_message = "The native application options should be set for Connectivity Client access"
  }
}

run "customer_managed_key" {
  command = apply

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_verifiedaccess_trust_provider.user[0].sse_specification[0].kms_key_arn == "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The trust provider should be encrypted with the supplied key"
  }
}

run "created_key" {
  command = apply

  variables {
    create_kms_key = true
  }

  override_data {
    target = data.aws_region.current
    values = { region = "eu-west-2" }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }

  override_resource {
    target = aws_kms_key.current
    values = { arn = "arn:aws:kms:eu-west-2:111111111111:key/22222222-2222-2222-2222-222222222222" }
  }

  assert {
    condition     = aws_kms_key.current[0].enable_key_rotation == true && aws_kms_alias.current[0].name == "alias/verified-access-test"
    error_message = "A rotated key with the alias alias/<name_prefix>-<name> should be created"
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_kms_key.current[0].policy).Statement :
      statement.Sid == "AllowVerifiedAccess" &&
      contains(statement.Action, "kms:CreateGrant") &&
      statement.Condition.StringEquals["kms:ViaService"] == "verified-access.eu-west-2.amazonaws.com" &&
      statement.Condition.StringEquals["kms:CallerAccount"] == "111111111111"
    ])
    error_message = "The key policy should permit use only via Verified Access in this region and account"
  }

  assert {
    condition = alltrue([
      aws_verifiedaccess_trust_provider.user[0].sse_specification[0].kms_key_arn == aws_kms_key.current[0].arn,
      module.groups["platform-engineers"].id != null,
      output.kms_key_arn == aws_kms_key.current[0].arn,
    ])
    error_message = "The trust provider should be encrypted with the created key, which is exported"
  }
}

run "fips_enabled" {
  command = plan

  variables {
    fips_enabled = true
  }

  override_data {
    target = data.aws_region.current
    values = { region = "us-east-1" }
  }

  assert {
    condition     = aws_verifiedaccess_instance.current[0].fips_enabled == true
    error_message = "FIPS endpoints should be configurable on the instance"
  }
}

run "fips_disabled_by_default" {
  command = plan

  assert {
    condition     = aws_verifiedaccess_instance.current[0].fips_enabled == false
    error_message = "FIPS endpoints should be off by default"
  }
}

run "fips_unsupported_region" {
  command = plan

  variables {
    fips_enabled = true
  }

  override_data {
    target = data.aws_region.current
    values = { region = "eu-west-2" }
  }

  ## The check warns rather than blocks; terraform test reports it as a failure we expect
  expect_failures = [check.fips_region]
}

run "oidc_separate_native_client" {
  command = apply

  variables {
    oidc_client_secret        = "not-a-real-secret"
    oidc_native_client_secret = "not-a-real-native-secret"
    user_trust_provider = {
      type                  = "oidc"
      policy_reference_name = "okta"
      oidc = {
        issuer                      = "https://example.okta.com"
        authorization_endpoint      = "https://example.okta.com/oauth2/v1/authorize"
        token_endpoint              = "https://example.okta.com/oauth2/v1/token"
        user_info_endpoint          = "https://example.okta.com/oauth2/v1/userinfo"
        client_id                   = "browser"
        public_signing_key_endpoint = "https://example.okta.com/oauth2/v1/keys"
        native_client_id            = "native"
        native_scope                = "openid email groups offline_access profile"
      }
    }
    groups = {
      engineers = {
        policy = {
          identity_groups = ["engineers"]
          owner           = "platform-team"
          justification   = "Engineers reach internal tooling"
        }
        endpoints = {
          tools-web = {
            type                   = "load-balancer"
            protocol               = "https"
            port                   = 443
            application_domain     = "tools.example.com"
            domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/00000000-0000-0000-0000-000000000000"
            load_balancer_arn      = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/tools/abc"
          }
        }
      }
    }
  }

  assert {
    condition = alltrue([
      aws_verifiedaccess_trust_provider.user[0].oidc_options[0].client_id == "browser",
      aws_verifiedaccess_trust_provider.user[0].oidc_options[0].client_secret == "not-a-real-secret",
      aws_verifiedaccess_trust_provider.user[0].native_application_oidc_options[0].client_id == "native",
      aws_verifiedaccess_trust_provider.user[0].native_application_oidc_options[0].client_secret == "not-a-real-native-secret",
      aws_verifiedaccess_trust_provider.user[0].native_application_oidc_options[0].scope == "openid email groups offline_access profile",
    ])
    error_message = "The native application should use its own client, secret and scope"
  }

  assert {
    condition     = output.oidc_redirect_uris["tools-web"] == "https://tools.example.com/oauth2/idpresponse" && length(output.oidc_redirect_uris) == 1
    error_message = "The OIDC redirect URI of each http and https endpoint should be exported"
  }
}

run "oidc_native_client_defaults_to_browser_client" {
  command = apply

  variables {
    oidc_client_secret = "not-a-real-secret"
    user_trust_provider = {
      type = "oidc"
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
    condition = alltrue([
      aws_verifiedaccess_trust_provider.user[0].native_application_oidc_options[0].client_id == "client",
      aws_verifiedaccess_trust_provider.user[0].native_application_oidc_options[0].client_secret == "not-a-real-secret",
      aws_verifiedaccess_trust_provider.user[0].native_application_oidc_options[0].scope == "openid email groups offline_access",
    ])
    error_message = "The native application should reuse the browser client by default"
  }
}

run "outputs_and_tags" {
  command = apply

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["11111111-1111-1111-1111-111111111111"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        tags = {
          CostCentre = "platform"
          Owner      = "platform-team"
        }
        endpoints = {
          demo-ssh = {
            type        = "cidr"
            cidr        = "10.101.0.0/24"
            port_ranges = [{ from_port = 22, to_port = 22 }]
            tags = {
              CostCentre = "tenant-a"
            }
          }
        }
      }
    }
  }

  override_data {
    target = data.aws_region.current
    values = { region = "eu-west-2" }
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }

  assert {
    condition     = output.instance_arn == format("arn:aws:ec2:eu-west-2:111111111111:verified-access-instance/%s", aws_verifiedaccess_instance.current[0].id)
    error_message = "The instance ARN should be exported"
  }

  assert {
    condition     = output.group_arns["platform-engineers"] == module.groups["platform-engineers"].arn
    error_message = "The group ARNs should be exported"
  }

  assert {
    condition     = output.endpoint_device_validation_domains["demo-ssh"] == module.endpoints["demo-ssh"].device_validation_domain
    error_message = "The endpoint device validation domains should be exported"
  }

  assert {
    condition     = output.client_configuration_command == format("aws ec2 export-verified-access-instance-client-configuration --verified-access-instance-id %s --region eu-west-2 > ClientConfig-test.json", aws_verifiedaccess_instance.current[0].id)
    error_message = "The client configuration command should be exported"
  }

  assert {
    condition     = length(output.oidc_redirect_uris) == 0 && length(output.application_domains) == 0 && length(output.target_group_arns) == 0
    error_message = "The OIDC, application and target group outputs should be empty when not applicable"
  }

  assert {
    condition = alltrue([
      local.endpoints["demo-ssh"].tags["CostCentre"] == "tenant-a",
      local.endpoints["demo-ssh"].tags["Owner"] == "platform-team",
      local.endpoints["demo-ssh"].tags["Environment"] == "Testing",
      !contains(keys(aws_verifiedaccess_instance.current[0].tags), "CostCentre"),
    ])
    error_message = "Group tags should be merged over the module tags on the group and its endpoints, and endpoint tags over both"
  }
}

run "endpoint_subnets_in_the_vpc" {
  command = plan

  variables {
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
            subnet_ids  = ["subnet-0123456789abcdef2"]
          }
        }
      }
    }
  }

  override_data {
    target = data.aws_subnet.endpoint["subnet-0123456789abcdef2"]
    values = { vpc_id = "vpc-0123456789abcdef0" }
  }

  assert {
    condition     = length(data.aws_subnet.endpoint) == 1
    error_message = "Overridden endpoint subnets should be checked"
  }
}

run "endpoint_subnets_in_another_vpc" {
  command = plan

  variables {
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
            subnet_ids  = ["subnet-0123456789abcdef2"]
          }
        }
      }
    }
  }

  override_data {
    target = data.aws_subnet.endpoint["subnet-0123456789abcdef2"]
    values = { vpc_id = "vpc-0fedcba9876543210" }
  }

  expect_failures = [data.aws_subnet.endpoint]
}
