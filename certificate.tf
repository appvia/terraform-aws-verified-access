locals {
  ## Indicates the module requests a wildcard certificate for the http and https endpoints
  enable_certificate = var.certificate != null
  ## The certificate used by http and https endpoints without their own; with wait_for_validation the endpoints are
  ## only created once the certificate is issued
  certificate_arn = !local.enable_certificate ? null : (
    var.certificate.wait_for_validation ? aws_acm_certificate_validation.current[0].certificate_arn : aws_acm_certificate.current[0].arn
  )
}

## Request a wildcard public certificate for the http and https endpoints, validated by DNS records published in the
## domain's zone: by the module with dns, or by the caller (output certificate_validation_records) wherever it is hosted
resource "aws_acm_certificate" "current" {
  count = local.enable_certificate ? 1 : 0

  domain_name       = format("*.%s", var.certificate.domain_name)
  tags              = merge(local.tags, { Name = local.resource_name })
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

## Wait for the certificate to be issued, once the validation records are published (by the module with dns, so it
## waits for those records first)
resource "aws_acm_certificate_validation" "current" {
  count = local.enable_certificate && try(var.certificate.wait_for_validation, false) ? 1 : 0

  certificate_arn         = aws_acm_certificate.current[0].arn
  validation_record_fqdns = local.enable_validation_records ? [for record in aws_route53_record.validation : record.fqdn] : null
}
