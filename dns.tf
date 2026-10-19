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
  ## Indicates the module publishes application records, so it reads the hosted zone's name
  enable_application_records = local.enable_dns && try(var.dns.create_application_records, false) && length(local.application_endpoints) > 0
  ## The name of the hosted zone, lowercase and without the trailing dot
  dns_zone_name = local.enable_application_records ? trimsuffix(lower(data.aws_route53_zone.current[0].name), ".") : ""
  ## The application domains inside the hosted zone (below its apex, where a CNAME is allowed), which the module
  ## publishes; the others are left to the caller (output application_domains), as Route 53 rejects a record outside
  ## its zone
  application_records = {
    for name, domain in local.application_endpoints : name => domain
    if local.enable_application_records && endswith(trimsuffix(lower(domain), "."), format(".%s", local.dns_zone_name))
  }
}

## Find the hosted zone, whose name decides which application domains it can hold a record for
data "aws_route53_zone" "current" {
  count = local.enable_application_records ? 1 : 0

  zone_id = var.dns.zone_id
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

## Point each application domain in the hosted zone at the endpoint domain Verified Access generated for it
resource "aws_route53_record" "application" {
  for_each = local.application_records

  name    = each.value
  records = [module.endpoints[each.key].endpoint_domain]
  ttl     = var.dns.ttl
  type    = "CNAME"
  zone_id = var.dns.zone_id
}
