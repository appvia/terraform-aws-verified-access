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
            cedar         = "permit(principal, action, resource)\nwhen {\n  context.idc.groups has \"11111111-1111-1111-1111-111111111111\" &&\n  context.tcp_flow.client_ip == \"192.0.2.10\"\n};"
            owner         = "security-team"
            justification = "Break-glass access restricted to the incident response jump IP"
          }
        }
      }
    }
    auditors = {
      raw_policy = {
        cedar         = "permit(principal, action, resource)\nwhen {\n  context.idc.groups has \"e242c5b0-6081-1845-6fa8-6e0d9513c107\"\n};\nforbid(principal, action, resource)\nunless {\n  context has \"http_request\" && context.http_request.http_method == \"GET\"\n};"
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

run "identity_center_group_policy_with_verified_email" {
  command = plan

  variables {
    user_trust_provider = {
      type                   = "iam-identity-center"
      require_verified_email = true
    }
  }

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-identity-center-verified-email.cedar")
    error_message = "The group policy with verified email should match tests/golden/group-identity-center-verified-email.cedar"
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

## A group name is escaped for its Cedar string literal, so one holding a quote cannot close the string and OR in
## conditions of its own (`x") || true || ["y` would otherwise permit everyone), and a backslash stays a backslash
run "oidc_group_policy_escapes_group_names" {
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
          identity_groups = ["x\") || true || [\"y", "CORP\\admins"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
      }
    }
  }

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-oidc-escaped.cedar")
    error_message = "The OIDC group names should be escaped as in tests/golden/group-oidc-escaped.cedar"
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

run "structured_endpoint_policy" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["11111111-1111-1111-1111-111111111111", "d242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          ## Narrows the group to one of its identity groups, adds a condition and requires device posture
          demo-ssh = {
            type        = "cidr"
            cidr        = "10.101.0.0/24"
            port_ranges = [{ from_port = 22, to_port = 22 }]
            sensitive   = true
            policy = {
              identity_groups       = ["d242c5b0-6081-1845-6fa8-6e0d9513c107"]
              additional_conditions = ["context.idc.user.email.address like \"*@example.com\" || context.idc.user.email.address like \"*@example.org\""]
              owner                 = "security-team"
              justification         = "Only the on-call group may reach the production database hosts"
            }
          }
          ## Inherits the group's owner and justification
          demo-db = {
            type = "rds"
            port = 5432
            rds = {
              instance_arn = "arn:aws:rds:eu-west-2:111111111111:db:demo"
              endpoint     = "demo.abc.eu-west-2.rds.amazonaws.com"
            }
            policy = {
              identity_groups = ["11111111-1111-1111-1111-111111111111"]
            }
          }
        }
      }
    }
  }

  assert {
    condition     = output.rendered_policies["endpoint/demo-ssh"] == file("./tests/golden/endpoint-structured.cedar")
    error_message = "The structured endpoint policy should match tests/golden/endpoint-structured.cedar"
  }

  assert {
    condition     = output.rendered_policies["endpoint/demo-db"] == file("./tests/golden/endpoint-structured-group-owner.cedar")
    error_message = "The structured endpoint policy without its own owner should match tests/golden/endpoint-structured-group-owner.cedar"
  }

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-identity-center.cedar")
    error_message = "An endpoint policy should not change its group policy"
  }
}

run "oidc_groups_claim" {
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
        groups_claim           = "additional_user_context.groups"
      }
    }
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["platform-engineers", "admins"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-ssh = {
            type        = "cidr"
            cidr        = "10.101.0.0/24"
            port_ranges = [{ from_port = 22, to_port = 22 }]
            policy = {
              identity_groups = ["admins"]
            }
          }
        }
      }
    }
  }

  assert {
    condition     = output.rendered_policies["group/platform-engineers"] == file("./tests/golden/group-oidc-groups-claim.cedar")
    error_message = "The OIDC group policy with a groups claim should match tests/golden/group-oidc-groups-claim.cedar"
  }

  assert {
    condition     = output.rendered_policies["endpoint/demo-ssh"] == file("./tests/golden/endpoint-structured-oidc.cedar")
    error_message = "The OIDC endpoint policy should match tests/golden/endpoint-structured-oidc.cedar"
  }
}
