# Verified Access Endpoint

Provisions a single Verified Access endpoint (load-balancer, network-interface, cidr or rds) with a least privilege security group that may only reach the endpoint target on its ports.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_security_group.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_verifiedaccess_endpoint.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/verifiedaccess_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_application_domain"></a> [application\_domain](#input\_application\_domain) | The public DNS name users browse to (http and https endpoints only) | `string` | `null` | no |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | The CIDR block reached through the endpoint (cidr endpoints) | `string` | `null` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Create the endpoint security group, permitting traffic only to the targets on the endpoint ports; false uses only security\_group\_ids | `bool` | `true` | no |
| <a name="input_description"></a> [description](#input\_description) | The description of the Verified Access endpoint | `string` | `null` | no |
| <a name="input_domain_certificate_arn"></a> [domain\_certificate\_arn](#input\_domain\_certificate\_arn) | The public ACM certificate for the application domain (http and https endpoints only) | `string` | `null` | no |
| <a name="input_egress_cidr_blocks"></a> [egress\_cidr\_blocks](#input\_egress\_cidr\_blocks) | The CIDR blocks the endpoint security group may send to; cidr endpoints always use their own CIDR | `list(string)` | <pre>[<br/>  "10.0.0.0/8"<br/>]</pre> | no |
| <a name="input_endpoint_domain_prefix"></a> [endpoint\_domain\_prefix](#input\_endpoint\_domain\_prefix) | The prefix for the generated endpoint domain, defaults to the endpoint name | `string` | `null` | no |
| <a name="input_group_id"></a> [group\_id](#input\_group\_id) | The id of the Verified Access group the endpoint belongs to | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | An optional customer managed KMS key used to encrypt the endpoint | `string` | `null` | no |
| <a name="input_load_balancer_arn"></a> [load\_balancer\_arn](#input\_load\_balancer\_arn) | The internal load balancer reached through the endpoint (load-balancer endpoints) | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the Verified Access endpoint | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | The prefix of the endpoint security group name, following the caller's naming convention | `string` | `"verified-access"` | no |
| <a name="input_network_interface_id"></a> [network\_interface\_id](#input\_network\_interface\_id) | The network interface reached through the endpoint (network-interface endpoints) | `string` | `null` | no |
| <a name="input_policy_document"></a> [policy\_document](#input\_policy\_document) | An optional rendered Cedar policy for the endpoint, evaluated in addition to the group policy | `string` | `null` | no |
| <a name="input_port"></a> [port](#input\_port) | The port for http, https and rds endpoints | `number` | `null` | no |
| <a name="input_port_ranges"></a> [port\_ranges](#input\_port\_ranges) | The port ranges for tcp endpoints | <pre>list(object({<br/>    from_port = number<br/>    to_port   = number<br/>  }))</pre> | `[]` | no |
| <a name="input_protocol"></a> [protocol](#input\_protocol) | The protocol of the endpoint (http, https, tcp) | `string` | `"tcp"` | no |
| <a name="input_rds"></a> [rds](#input\_rds) | The RDS target for rds endpoints; set exactly one of the arns | <pre>object({<br/>    instance_arn = optional(string, null)<br/>    cluster_arn  = optional(string, null)<br/>    proxy_arn    = optional(string, null)<br/>    endpoint     = string<br/>  })</pre> | `null` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Additional security groups to attach to the endpoint; with create\_security\_group false, the only ones | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The subnets for the endpoint network interfaces | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags to apply to all resources | `map(string)` | n/a | yes |
| <a name="input_type"></a> [type](#input\_type) | The type of endpoint (load-balancer, network-interface, cidr, rds) | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC holding the endpoint subnets, used for the endpoint security group | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_device_validation_domain"></a> [device\_validation\_domain](#output\_device\_validation\_domain) | The domain Verified Access uses to validate devices for the endpoint |
| <a name="output_endpoint_domain"></a> [endpoint\_domain](#output\_endpoint\_domain) | The DNS name generated by Verified Access for the endpoint |
| <a name="output_id"></a> [id](#output\_id) | The id of the Verified Access endpoint |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The id of the security group the module created for the endpoint network interfaces, null with create\_security\_group false |
<!-- END_TF_DOCS -->
