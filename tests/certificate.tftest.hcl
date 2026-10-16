## Certificate tests: the module requests a DNS validated wildcard certificate, exports its validation records and
## uses it for http and https endpoints without their own certificate.

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

  mock_resource "aws_acm_certificate_validation" {
    defaults = {
      certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/11111111-1111-1111-1111-111111111111"
    }
  }
}

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

  certificate = {
    domain_name = "example.com"
  }

  groups = {
    platform-engineers = {
      policy = {
        identity_groups = ["11111111-1111-1111-1111-111111111111"]
        owner           = "platform-team"
        justification   = "Platform engineers use the internal web tools"
      }
      endpoints = {
        app-web = {
          type               = "load-balancer"
          protocol           = "http"
          port               = 80
          application_domain = "app.example.com"
          load_balancer_arn  = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/demo/abc"
        }
        own-certificate = {
          type                   = "load-balancer"
          protocol               = "https"
          port                   = 443
          application_domain     = "tools.other.example.org"
          domain_certificate_arn = "arn:aws:acm:eu-west-2:111111111111:certificate/22222222-2222-2222-2222-222222222222"
          load_balancer_arn      = "arn:aws:elasticloadbalancing:eu-west-2:111111111111:loadbalancer/app/demo/abc"
        }
        app-ssh = {
          type        = "cidr"
          cidr        = "10.10.0.0/24"
          port_ranges = [{ from_port = 22, to_port = 22 }]
        }
      }
    }
  }
}

run "wildcard_certificate" {
  command = apply

  assert {
    condition     = aws_acm_certificate.current[0].domain_name == "*.example.com" && aws_acm_certificate.current[0].validation_method == "DNS"
    error_message = "A DNS validated wildcard certificate should be requested for the domain"
  }

  assert {
    condition     = aws_acm_certificate.current[0].tags["Name"] == "verified-access-test"
    error_message = "The certificate should be named verified-access-<name>"
  }

  assert {
    condition     = length(aws_acm_certificate_validation.current) == 0
    error_message = "The module should not wait for validation by default"
  }

  assert {
    condition     = local.endpoint_targets["app-web"].domain_certificate_arn == aws_acm_certificate.current[0].arn
    error_message = "An http endpoint without its own certificate should use the module certificate"
  }

  assert {
    condition     = local.endpoint_targets["own-certificate"].domain_certificate_arn == "arn:aws:acm:eu-west-2:111111111111:certificate/22222222-2222-2222-2222-222222222222"
    error_message = "An endpoint with its own certificate should keep it"
  }

  assert {
    condition     = local.endpoint_targets["app-ssh"].domain_certificate_arn == null
    error_message = "A tcp endpoint should not use a certificate"
  }

  assert {
    condition     = output.certificate_arn == aws_acm_certificate.current[0].arn
    error_message = "The certificate should be exported"
  }

  assert {
    condition     = output.certificate_validation_records["_0123456789abcdef.example.com."] == "_fedcba9876543210.acm-validations.aws."
    error_message = "The validation records should be exported as name => value"
  }
}

run "wait_for_validation" {
  command = apply

  variables {
    certificate = {
      domain_name         = "example.com"
      wait_for_validation = true
    }
  }

  assert {
    condition     = aws_acm_certificate_validation.current[0].certificate_arn == aws_acm_certificate.current[0].arn
    error_message = "The module should wait for the certificate to be issued"
  }

  assert {
    condition     = local.endpoint_targets["app-web"].domain_certificate_arn == aws_acm_certificate_validation.current[0].certificate_arn
    error_message = "Endpoints should use the validated certificate, so they are created after it is issued"
  }
}

run "no_certificate" {
  command = plan

  variables {
    certificate = null
    groups      = {}
  }

  assert {
    condition     = length(aws_acm_certificate.current) == 0 && length(aws_acm_certificate_validation.current) == 0
    error_message = "No certificate should be requested by default"
  }

  assert {
    condition     = output.certificate_arn == null && length(output.certificate_validation_records) == 0
    error_message = "The certificate outputs should be empty without a certificate"
  }
}

run "route53_records" {
  command = apply

  variables {
    certificate = {
      domain_name         = "example.com"
      wait_for_validation = true
    }
    dns = {
      zone_id = "Z0123456789ABCDEFGHIJ"
      ttl     = 60
    }
  }

  assert {
    condition = alltrue([
      aws_route53_record.validation["*.example.com"].name == "_0123456789abcdef.example.com.",
      aws_route53_record.validation["*.example.com"].type == "CNAME",
      aws_route53_record.validation["*.example.com"].records == toset(["_fedcba9876543210.acm-validations.aws."]),
      aws_route53_record.validation["*.example.com"].zone_id == "Z0123456789ABCDEFGHIJ",
      aws_route53_record.validation["*.example.com"].ttl == 60,
    ])
    error_message = "The certificate validation record should be published in the hosted zone"
  }

  assert {
    condition     = aws_acm_certificate_validation.current[0].validation_record_fqdns == toset([aws_route53_record.validation["*.example.com"].fqdn])
    error_message = "The module should wait for validation through the records it publishes"
  }

  assert {
    condition     = toset(keys(aws_route53_record.application)) == toset(["app-web", "own-certificate"])
    error_message = "An application record should be published for each http and https endpoint, not tcp endpoints"
  }

  assert {
    condition = alltrue([
      aws_route53_record.application["app-web"].name == "app.example.com",
      aws_route53_record.application["app-web"].type == "CNAME",
      aws_route53_record.application["app-web"].records == toset([output.endpoint_domains["app-web"]]),
    ])
    error_message = "The application domain should be a CNAME of the endpoint domain"
  }

  assert {
    condition     = output.application_domains["app.example.com"] == output.endpoint_domains["app-web"] && length(output.application_domains) == 2
    error_message = "The application domains should be exported with their CNAME target"
  }
}

run "route53_application_records_only" {
  command = plan

  variables {
    dns = {
      zone_id                   = "Z0123456789ABCDEFGHIJ"
      create_validation_records = false
    }
  }

  assert {
    condition     = length(aws_route53_record.validation) == 0 && length(aws_route53_record.application) == 2
    error_message = "The validation records should be optional"
  }
}

run "route53_disabled" {
  command = plan

  assert {
    condition     = length(aws_route53_record.validation) == 0 && length(aws_route53_record.application) == 0
    error_message = "No records should be published without dns"
  }

  assert {
    condition     = aws_acm_certificate_validation.current == []
    error_message = "No validation should be waited for by default"
  }
}
