
## Warn when the instance has no access logging configured; logging is optional so examples and tests can omit it
check "access_logs" {
  assert {
    condition     = var.access_logs != null
    error_message = "Verified Access access logging is disabled, so access attempts will not be recorded. Set var.access_logs for any live environment."
  }
}
