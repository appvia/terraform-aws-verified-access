# Verified Access Group

Provisions a single Verified Access group with its rendered Cedar policy. Used by the root module; the policy is rendered by the root module from structured input.

<!-- BEGIN_TF_DOCS -->
## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_instance_id"></a> [instance\_id](#input\_instance\_id) | The id of the Verified Access instance the group belongs to | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name of the Verified Access group | `string` | n/a | yes |
| <a name="input_policy_document"></a> [policy\_document](#input\_policy\_document) | The rendered Cedar policy for the group | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags to apply to all resources | `map(string)` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | The description of the Verified Access group | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | An optional customer managed KMS key used to encrypt the group | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | The ARN of the Verified Access group |
| <a name="output_id"></a> [id](#output\_id) | The id of the Verified Access group |
<!-- END_TF_DOCS -->
