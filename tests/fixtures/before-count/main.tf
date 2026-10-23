## The addresses a deployment made before the instance, user trust provider and its attachment (root module) and the
## endpoint security group (endpoint module) were created with count; tests/moved.tftest.hcl applies this first, then
## the module, to prove the moved blocks keep them

resource "aws_verifiedaccess_instance" "current" {}

resource "aws_verifiedaccess_trust_provider" "user" {
  policy_reference_name    = "idc"
  trust_provider_type      = "user"
  user_trust_provider_type = "iam-identity-center"
}

resource "aws_verifiedaccess_instance_trust_provider_attachment" "user" {
  verifiedaccess_instance_id       = aws_verifiedaccess_instance.current.id
  verifiedaccess_trust_provider_id = aws_verifiedaccess_trust_provider.user.id
}

module "endpoints" {
  for_each = toset(["demo-ssh"])
  source   = "./endpoint"
}

output "instance_id" {
  value = aws_verifiedaccess_instance.current.id
}

output "user_trust_provider_id" {
  value = aws_verifiedaccess_trust_provider.user.id
}

output "user_attachment_id" {
  value = aws_verifiedaccess_instance_trust_provider_attachment.user.id
}

output "endpoint_security_group_id" {
  value = module.endpoints["demo-ssh"].security_group_id
}
