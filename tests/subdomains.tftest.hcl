## Several web applications on one domain: app.example.com and app1.example.com share the module's wildcard
## certificate, are reached by different Identity Center groups and are sent to different targets (the example in the
## README, "Several web applications on one domain").

mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:eu-west-2:111111111111:certificate/11111111-1111-1111-1111-111111111111"
      domain_validation_options = [
        {
          domain_name           = "*.example.com"
          resource_record_name  = "_0123456789abcdef.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_fedcba9876543210.acm-validations.aws."
        }
      ]
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/net/verified-access-test/0123456789abcdef"
      arn_suffix = "net/verified-access-test/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:targetgroup/verified-access/0123456789abcdef"
    }
  }

  override_data {
    target = data.aws_subnet.load_balancer[0]
    values = { cidr_block = "10.10.0.0/24" }
  }

  override_data {
    target = data.aws_subnet.load_balancer[1]
    values = { cidr_block = "10.10.1.0/24" }
  }
}

variables {
  name       = "test"
  topology   = "hub"
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

  certificate = {
    domain_name = "example.com"
  }

  groups = {
    app-users = {
      policy = {
        identity_groups = ["11111111-1111-1111-1111-111111111111"]
        owner           = "app-team"
        justification   = "The app team uses the app application"
      }
      endpoints = {
        app = {
          type               = "load-balancer"
          protocol           = "http"
          port               = 80
          application_domain = "app.example.com"
          targets            = ["10.50.0.20"]
          listener_port      = 8001
        }
      }
    }
    app1-users = {
      policy = {
        identity_groups = ["22222222-2222-2222-2222-222222222222"]
        owner           = "finance-team"
        justification   = "The finance team uses the app1 application"
      }
      endpoints = {
        app1 = {
          type               = "load-balancer"
          protocol           = "http"
          port               = 80
          application_domain = "app1.example.com"
          targets            = ["10.50.1.30", "10.50.1.31"]
          listener_port      = 8002
        }
      }
    }
  }
}

run "subdomains_on_one_domain" {
  command = apply

  assert {
    condition     = aws_acm_certificate.current[0].domain_name == "*.example.com"
    error_message = "One wildcard certificate should cover every application domain"
  }

  assert {
    condition = alltrue([
      local.endpoint_targets["app"].domain_certificate_arn == aws_acm_certificate.current[0].arn,
      local.endpoint_targets["app1"].domain_certificate_arn == aws_acm_certificate.current[0].arn,
    ])
    error_message = "Both endpoints should use the module's wildcard certificate"
  }

  assert {
    condition     = aws_lb_listener.current["app"].port == 8001 && aws_lb_listener.current["app1"].port == 8002
    error_message = "Each application should have its own listener on the central load balancer"
  }

  assert {
    condition = alltrue([
      aws_lb_target_group.current["app"].port == 80,
      aws_lb_target_group.current["app1"].port == 80,
      aws_lb_target_group_attachment.current["app-10.50.0.20"].target_id == "10.50.0.20",
      aws_lb_target_group_attachment.current["app1-10.50.1.30"].target_id == "10.50.1.30",
      aws_lb_target_group_attachment.current["app1-10.50.1.31"].target_id == "10.50.1.31",
      !contains(keys(aws_lb_target_group_attachment.current), "app-10.50.1.30"),
    ])
    error_message = "Each application should send to its own targets on port 80"
  }

  assert {
    condition = alltrue([
      strcontains(output.rendered_policies["group/app-users"], "11111111-1111-1111-1111-111111111111"),
      !strcontains(output.rendered_policies["group/app-users"], "22222222-2222-2222-2222-222222222222"),
      strcontains(output.rendered_policies["group/app1-users"], "22222222-2222-2222-2222-222222222222"),
      !strcontains(output.rendered_policies["group/app1-users"], "11111111-1111-1111-1111-111111111111"),
    ])
    error_message = "Each application should be reachable only by its own Identity Center group"
  }
}
