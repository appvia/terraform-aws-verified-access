## Golden file tests: the rendered Cedar for a given input must match tests/golden/*.cedar byte for byte,
## so any change to the policy interface that alters policy semantics is visible in the diff.

mock_provider "aws" {}

variables {
  name       = "test"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0"]

  tags = {
    "Environment" = "Testing"
    "GitRepo"     = "https://github.com/appvia/terraform-aws-verified-access"
  }

  user_trust_provider = {
    type = "iam-identity-center"
  }

  device_trust_provider = {
    type      = "crowdstrike"
    tenant_id = "tenant"
  }

  access_logs = {
    cloudwatch = {}
  }

  groups = {
    platform-engineers = {
      policy = {
        ## Out of order and duplicated on purpose: the rendered policy must be sorted and de-duplicated
        identity_groups = ["d242c5b0-6081-1845-6fa8-6e0d9513c107", "c242c5b0-6081-1845-6fa8-6e0d9513c107", "c242c5b0-6081-1845-6fa8-6e0d9513c107"]
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
        demo-db = {
          type = "rds"
          port = 5432
          rds = {
            instance_arn = "arn:aws:rds:eu-west-2:111111111111:db:demo"
            endpoint     = "demo.abc.eu-west-2.rds.amazonaws.com"
          }
        }
        demo-break-glass = {
          type        = "cidr"
          cidr        = "10.101.1.0/24"
          port_ranges = [{ from_port = 22, to_port = 22 }]
          raw_policy = {
            cedar         = "permit(principal, action, resource)\nwhen {\n  context.idc.groups has \"c242c5b0-6081-1845-6fa8-6e0d9513c107\" &&\n  context.tcp_flow.client_ip == \"192.0.2.10\"\n};"
            owner         = "security-team"
            justification = "Break-glass access restricted to the incident response jump IP"
          }
        }
      }
    }
    auditors = {
      raw_policy = {
        cedar         = "permit(principal, action, resource)\nwhen {\n  context.idc.groups has \"e242c5b0-6081-1845-6fa8-6e0d9513c107\"\n};\nforbid(principal, action, resource)\nwhen {\n  context.http_request.http_method != \"GET\"\n};"
        owner         = "security-team"
        justification = "Auditors are read-only: deny every non-GET request"
      }
    }
  }
}

run "identity_center_group_policy" {
  command = plan

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-identity-center.cedar")
    error_message = "The Identity Center group policy should match tests/golden/group-identity-center.cedar"
  }
}

run "identity_center_group_policy_without_verified_email" {
  command = plan

  variables {
    user_trust_provider = {
      type                   = "iam-identity-center"
      require_verified_email = false
    }
  }

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-identity-center-no-email.cedar")
    error_message = "The group policy without verified email should match tests/golden/group-identity-center-no-email.cedar"
  }
}

run "oidc_group_policy" {
  command = plan

  variables {
    oidc_client_secret = "x"
    user_trust_provider = {
      type                  = "oidc"
      policy_reference_name = "okta"
      oidc = {
        issuer                 = "https://example.okta.com"
        authorization_endpoint = "https://example.okta.com/a"
        token_endpoint         = "https://example.okta.com/t"
        user_info_endpoint     = "https://example.okta.com/u"
        client_id              = "c"
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
    error_message = "The OIDC group policy should match tests/golden/group-oidc.cedar"
  }
}

run "raw_group_policy" {
  command = plan

  assert {
    condition     = output.rendered_policies["group/auditors"] == file("./tests/golden/group-raw.cedar")
    error_message = "The raw group policy should match tests/golden/group-raw.cedar"
  }
}

run "crowdstrike_sensitive_endpoint_policy" {
  command = plan

  assert {
    condition     = output.rendered_policies["endpoint/demo-ssh"] == file("./tests/golden/endpoint-crowdstrike.cedar")
    error_message = "The CrowdStrike sensitive endpoint policy should match tests/golden/endpoint-crowdstrike.cedar"
  }
}

run "jamf_sensitive_endpoint_policy" {
  command = plan

  variables {
    device_trust_provider = {
      type              = "jamf"
      tenant_id         = "t"
      jamf_allowed_risk = ["SECURE", "LOW"]
    }
  }

  assert {
    condition     = output.rendered_policies["endpoint/demo-ssh"] == file("./tests/golden/endpoint-jamf.cedar")
    error_message = "The Jamf sensitive endpoint policy should match tests/golden/endpoint-jamf.cedar"
  }
}

run "jumpcloud_sensitive_endpoint_policy" {
  command = plan

  variables {
    device_trust_provider = {
      type      = "jumpcloud"
      tenant_id = "t"
    }
  }

  assert {
    condition     = output.rendered_policies["endpoint/demo-ssh"] == file("./tests/golden/endpoint-jumpcloud.cedar")
    error_message = "The JumpCloud sensitive endpoint policy should match tests/golden/endpoint-jumpcloud.cedar"
  }
}

run "raw_endpoint_policy" {
  command = plan

  assert {
    condition     = output.rendered_policies["endpoint/demo-break-glass"] == file("./tests/golden/endpoint-raw.cedar")
    error_message = "The raw endpoint policy should match tests/golden/endpoint-raw.cedar"
  }
}

run "non_sensitive_endpoint_has_no_policy" {
  command = plan

  assert {
    condition     = !contains(keys(output.rendered_policies), "endpoint/demo-db")
    error_message = "A non-sensitive endpoint without a raw policy should rely on its group policy only"
  }

  assert {
    condition     = length(output.rendered_policies) == 4
    error_message = "Two group policies and two endpoint policies should be rendered"
  }
}
