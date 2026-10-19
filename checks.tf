
## Warn when the instance has no access logging configured; logging is optional so examples and tests can omit it,
## and an existing instance's logging is owned elsewhere
check "access_logs" {
  assert {
    condition     = var.access_logs != null || var.existing_instance != null
    error_message = "Verified Access access logging is disabled, so access attempts will not be recorded. Set var.access_logs for any live environment."
  }
}

## Warn when application domains are outside the hosted zone given in dns, so their CNAMEs are left to the caller
check "application_records" {
  assert {
    condition = length(local.application_records) == length(local.application_endpoints) || !local.enable_application_records
    error_message = format(
      "These application domains are not inside the Route 53 hosted zone %s, so the module publishes no CNAME for them; publish them where their domain is hosted (output application_domains): %s.",
      local.dns_zone_name,
      join(", ", sort([for name, domain in local.application_endpoints : domain if !contains(keys(local.application_records), name)])),
    )
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
