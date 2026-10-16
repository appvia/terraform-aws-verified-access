
## Warn when the instance has no access logging configured; logging is optional so examples and tests can omit it
check "access_logs" {
  assert {
    condition     = var.access_logs != null
    error_message = "Verified Access access logging is disabled, so access attempts will not be recorded. Set var.access_logs for any live environment."
  }
}

## Warn when FIPS endpoints are requested outside the regions Verified Access supports them in (US, Canada and AWS
## GovCloud (US)); AWS rejects the instance there
check "fips_region" {
  assert {
    condition     = !var.fips_enabled || can(regex("^(us|ca)-", data.aws_region.current.region))
    error_message = format("fips_enabled is only supported by Verified Access in US, Canada and AWS GovCloud (US) regions, not %s.", data.aws_region.current.region)
  }
}
