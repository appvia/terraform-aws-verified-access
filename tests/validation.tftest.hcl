## Input validation tests: every rule (V1-V21) has a run proving invalid input is rejected at plan time.
## Each invalid run breaks exactly one rule against the valid baseline below.

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
        identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
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

## Valid inputs

run "valid_baseline" {
  command = plan
}

run "valid_logging_disabled_warns" {
  command = plan

  variables {
    access_logs = null
  }

  expect_failures = [check.access_logs]
}

run "valid_oidc_provider" {
  command = plan

  variables {
    oidc_client_secret = "not-a-real-secret"
    user_trust_provider = {
      type                  = "oidc"
      policy_reference_name = "okta"
      oidc = {
        issuer                 = "https://example.okta.com"
        authorization_endpoint = "https://example.okta.com/oauth2/v1/authorize"
        token_endpoint         = "https://example.okta.com/oauth2/v1/token"
        user_info_endpoint     = "https://example.okta.com/oauth2/v1/userinfo"
        client_id              = "client"
      }
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
}

run "valid_sensitive_endpoint_with_device_provider" {
  command = plan

  variables {
    device_trust_provider = {
      type      = "crowdstrike"
      tenant_id = "tenant"
    }
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
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
}

## V1: name

run "invalid_name" {
  command = plan

  variables {
    name = "Not_Valid"
  }

  expect_failures = [var.name]
}

## V2-V4: user trust provider

run "invalid_user_provider_type" {
  command = plan

  variables {
    user_trust_provider = {
      type = "saml"
    }
  }

  expect_failures = [var.user_trust_provider]
}

run "invalid_policy_reference_name" {
  command = plan

  variables {
    user_trust_provider = {
      type                  = "iam-identity-center"
      policy_reference_name = "Not-Cedar"
    }
  }

  expect_failures = [var.user_trust_provider]
}

run "invalid_oidc_without_settings" {
  command = plan

  variables {
    oidc_client_secret = "not-a-real-secret"
    user_trust_provider = {
      type = "oidc"
    }
    groups = {}
  }

  expect_failures = [var.user_trust_provider]
}

run "invalid_oidc_without_secret" {
  command = plan

  variables {
    user_trust_provider = {
      type = "oidc"
      oidc = {
        issuer                 = "https://example.okta.com"
        authorization_endpoint = "https://example.okta.com/oauth2/v1/authorize"
        token_endpoint         = "https://example.okta.com/oauth2/v1/token"
        user_info_endpoint     = "https://example.okta.com/oauth2/v1/userinfo"
        client_id              = "client"
      }
    }
    groups = {}
  }

  expect_failures = [var.oidc_client_secret]
}

## V5-V7: device trust provider

run "invalid_device_provider_type" {
  command = plan

  variables {
    device_trust_provider = {
      type      = "intune"
      tenant_id = "tenant"
    }
  }

  expect_failures = [var.device_trust_provider]
}

run "invalid_crowdstrike_score" {
  command = plan

  variables {
    device_trust_provider = {
      type                  = "crowdstrike"
      tenant_id             = "tenant"
      crowdstrike_min_score = 101
    }
  }

  expect_failures = [var.device_trust_provider]
}

run "invalid_jamf_risk" {
  command = plan

  variables {
    device_trust_provider = {
      type              = "jamf"
      tenant_id         = "tenant"
      jamf_allowed_risk = ["LOWISH"]
    }
  }

  expect_failures = [var.device_trust_provider]
}

## V8: subnets

run "invalid_no_subnets" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

## V9: names

run "invalid_group_name" {
  command = plan

  variables {
    groups = {
      Platform_Engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_endpoint_name" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          "Demo SSH" = {
            type        = "cidr"
            cidr        = "10.101.0.0/24"
            port_ranges = [{ from_port = 22, to_port = 22 }]
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

## V10-V12: policies

run "invalid_policy_and_raw_policy" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        raw_policy = {
          cedar         = "permit(principal, action, resource) when { context.idc.user.email.verified == true };"
          owner         = "platform-team"
          justification = "Raw policy alongside a structured one"
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_no_policy" {
  command = plan

  variables {
    groups = {
      platform-engineers = {}
    }
  }

  expect_failures = [var.groups]
}

run "invalid_unscoped_policy" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = []
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_identity_center_group_name" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["Cloud Sandboxes"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_missing_owner" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = " "
          justification   = "Platform engineers operate the demo tenant hosts"
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_short_justification" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "because"
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_empty_raw_policy" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        raw_policy = {
          cedar         = "  "
          owner         = "security-team"
          justification = "Raw policy reviewed by the security team"
        }
      }
    }
  }

  expect_failures = [var.groups]
}

## V13-V14: endpoints

run "invalid_endpoint_type" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-ssh = {
            type        = "vpn"
            cidr        = "10.101.0.0/24"
            port_ranges = [{ from_port = 22, to_port = 22 }]
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_cidr_endpoint_http" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-web = {
            type                   = "cidr"
            protocol               = "https"
            cidr                   = "10.101.0.0/24"
            port                   = 443
            application_domain     = "demo.example.com"
            domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/abc"
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_missing_target" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-web = {
            type        = "load-balancer"
            port_ranges = [{ from_port = 443, to_port = 443 }]
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_cidr_value" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-ssh = {
            type        = "cidr"
            cidr        = "10.101.0.0/33"
            port_ranges = [{ from_port = 22, to_port = 22 }]
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_rds_multiple_targets" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-db = {
            type = "rds"
            port = 5432
            rds = {
              instance_arn = "arn:aws:rds:eu-west-2:111111111111:db:demo"
              cluster_arn  = "arn:aws:rds:eu-west-2:111111111111:cluster:demo"
              endpoint     = "demo.abc.eu-west-2.rds.amazonaws.com"
            }
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_port_range" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-ssh = {
            type        = "cidr"
            cidr        = "10.101.0.0/24"
            port_ranges = [{ from_port = 2222, to_port = 22 }]
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

run "invalid_http_without_domain" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
        endpoints = {
          demo-web = {
            type              = "load-balancer"
            protocol          = "https"
            port              = 443
            load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/demo/abc"
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

## V15: sensitive endpoints fail closed without a device provider

run "invalid_sensitive_without_device_provider" {
  command = plan

  variables {
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
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

  expect_failures = [var.groups]
}

## V16: endpoint names are unique across groups

run "invalid_duplicate_endpoint_names" {
  command = plan

  variables {
    groups = {
      team-a = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "team-a"
          justification   = "Team A operates the demo tenant hosts"
        }
        endpoints = {
          demo-ssh = {
            type        = "cidr"
            cidr        = "10.101.0.0/24"
            port_ranges = [{ from_port = 22, to_port = 22 }]
          }
        }
      }
      team-b = {
        policy = {
          identity_groups = ["d242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "team-b"
          justification   = "Team B operates the demo tenant hosts"
        }
        endpoints = {
          demo-ssh = {
            type        = "cidr"
            cidr        = "10.102.0.0/24"
            port_ranges = [{ from_port = 22, to_port = 22 }]
          }
        }
      }
    }
  }

  expect_failures = [var.groups]
}

## V17-V21: logging

run "invalid_logging_without_destination" {
  command = plan

  variables {
    access_logs = {}
  }

  expect_failures = [var.access_logs]
}

run "invalid_log_version" {
  command = plan

  variables {
    access_logs = {
      log_version = "ocsf-2.0"
      cloudwatch  = {}
    }
  }

  expect_failures = [var.access_logs]
}

run "invalid_trust_context_on_old_log_version" {
  command = plan

  variables {
    access_logs = {
      log_version           = "ocsf-0.1"
      include_trust_context = true
      cloudwatch            = {}
    }
    groups = {
      platform-engineers = {
        policy = {
          identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"]
          owner           = "platform-team"
          justification   = "Platform engineers operate the demo tenant hosts"
        }
      }
    }
  }

  expect_failures = [var.access_logs]
}

run "invalid_tcp_endpoint_on_old_log_version" {
  command = plan

  variables {
    access_logs = {
      log_version = "ocsf-0.1"
      cloudwatch  = {}
    }
  }

  expect_failures = [var.access_logs]
}

run "invalid_log_retention" {
  command = plan

  variables {
    access_logs = {
      cloudwatch = {
        retention_in_days = 45
      }
    }
  }

  expect_failures = [var.access_logs]
}
