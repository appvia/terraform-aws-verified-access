## The endpoint security group as it was before create_security_group, without count
resource "aws_security_group" "current" {
  name   = "verified-access-test-demo-ssh"
  vpc_id = "vpc-0123456789abcdef0"
}

output "security_group_id" {
  value = aws_security_group.current.id
}
