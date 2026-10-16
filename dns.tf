locals {
  ## Indicates the module publishes records in a Route 53 hosted zone
  enable_dns = var.dns != null
  ## Indicates the module publishes the validation records of its certificate
  enable_validation_records = local.enable_dns && local.enable_certificate ? var.dns.create_validation_records : false
  ## The domain names the module certificate is validated for, known at plan time
  certificate_domains = local.enable_certificate ? [format("*.%s", var.certificate.domain_name)] : []
  ## The http and https endpoints with an application domain, which users browse to
  application_endpoints = {
    for name, endpoint in local.endpoints : name => endpoint.application_domain if endpoint.protocol != "tcp" && endpoint.application_domain != null
  }
}

## Publish the certificate validation records in the hosted zone, keyed by the domains known at plan time
resource "aws_route53_record" "validation" {
  for_each = local.enable_validation_records ? toset(local.certificate_domains) : toset([])

  allow_overwrite = true
  name            = one([for option in aws_acm_certificate.current[0].domain_validation_options : option.resource_record_name if option.domain_name == each.value])
  records         = [one([for option in aws_acm_certificate.current[0].domain_validation_options : option.resource_record_value if option.domain_name == each.value])]
  ttl             = var.dns.ttl
  type            = one([for option in aws_acm_certificate.current[0].domain_validation_options : option.resource_record_type if option.domain_name == each.value])
  zone_id         = var.dns.zone_id
}

## Point each application domain at the endpoint domain Verified Access generated for it
resource "aws_route53_record" "application" {
  for_each = local.enable_dns && try(var.dns.create_application_records, false) ? local.application_endpoints : {}

  name    = each.value
  records = [module.endpoints[each.key].endpoint_domain]
  ttl     = var.dns.ttl
  type    = "CNAME"
  zone_id = var.dns.zone_id
}
