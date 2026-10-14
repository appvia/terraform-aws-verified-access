
output "arn" {
  description = "The ARN of the Verified Access group"
  value       = aws_verifiedaccess_group.current.verifiedaccess_group_arn
}

output "id" {
  description = "The id of the Verified Access group"
  value       = aws_verifiedaccess_group.current.id
}
