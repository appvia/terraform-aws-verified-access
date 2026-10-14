<!-- markdownlint-disable -->
<a href="https://www.appvia.io/"><img src="https://github.com/appvia/terraform-aws-verified-access/blob/main/docs/banner.jpg?raw=true" alt="Appvia Banner"/></a><br/><p align="right"> <a href="https://registry.terraform.io/modules/appvia/verified-access/aws/latest"><img src="https://img.shields.io/static/v1?label=APPVIA&message=Terraform%20Registry&color=191970&style=for-the-badge" alt="Terraform Registry"/></a></a> <a href="https://github.com/appvia/terraform-aws-verified-access/releases/latest"><img src="https://img.shields.io/github/release/appvia/terraform-aws-verified-access.svg?style=for-the-badge&color=006400" alt="Latest Release"/></a> <a href="https://appvia-community.slack.com/join/shared_invite/zt-1s7i7xy85-T155drryqU56emm09ojMVA#/shared-invite/email"><img src="https://img.shields.io/badge/Slack-Join%20Community-purple?style=for-the-badge&logo=slack" alt="Slack Community"/></a> <a href="https://github.com/appvia/terraform-aws-verified-access/graphs/contributors"><img src="https://img.shields.io/github/contributors/appvia/terraform-aws-verified-access.svg?style=for-the-badge&color=FF8C00" alt="Contributors"/></a>

<!-- markdownlint-restore -->
<!--
  ***** CAUTION: DO NOT EDIT ABOVE THIS LINE ******
-->

![Github Actions](https://github.com/appvia/terraform-aws-verified-access/actions/workflows/terraform.yml/badge.svg)

# Terraform AWS Verified Access

## Description

This module provisions [AWS Verified Access](https://docs.aws.amazon.com/verified-access/latest/ug/what-is-verified-access.html) as a managed, identity- and device-aware replacement for bastion hosts and hosted workstations. It manages the Verified Access instance, user and device trust providers, groups, endpoints (load balancer, network interface, CIDR and RDS) and access logging.

Access policies are declared as structured input and rendered to [Cedar](https://www.cedarpolicy.com/) by the module, so reviewers read who may reach what rather than raw policy. The module consumes an existing network (VPC and dedicated subnets) and never creates VPCs, subnets, load balancers, certificates or DNS records.

## Usage

```hcl
module "verified_access" {
  source  = "appvia/verified-access/aws"
  version = "0.1.0"

  name       = "production"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] # dedicated Verified Access subnets
  tags       = { Environment = "Production" }
  vpc_id     = "vpc-0123456789abcdef0"

  user_trust_provider = {
    type = "iam-identity-center"
  }

  access_logs = {
    include_trust_context = true
    cloudwatch            = {}
    s3                    = { bucket_name = "log-archive-verified-access", bucket_owner = "111111111111" }
  }

  groups = {
    platform-engineers = {
      policy = {
        identity_groups = ["c242c5b0-6081-1845-6fa8-6e0d9513c107"] # Identity Center group ids
        owner           = "platform-team"
        justification   = "Platform engineers administer the tenant hosts"
      }
      endpoints = {
        hosts-ssh = {
          type        = "cidr"
          cidr        = "10.101.0.0/24"
          port_ranges = [{ from_port = 22, to_port = 22 }]
        }
      }
    }
  }
}
```

See [examples/basic](examples/basic) for a complete, standalone deployment.

## Access policies

Policies are declared as structured input (`groups[*].policy`) and rendered to Cedar by the module; reviewers read the input and the `rendered_policies` output, not hand written Cedar.

- **Plan time validation** rejects malformed or over-broad input, e.g. an empty `identity_groups` (an unscoped permit), Identity Center group names instead of ids, or an endpoint marked `sensitive` without a `device_trust_provider`.
- **Sensitive endpoints** receive an endpoint policy requiring device posture; group and endpoint policies must both allow.
- **Escape hatch**: `raw_policy` accepts hand written Cedar where the structured input cannot express a rule. Keep raw policies in a dedicated directory protected by `CODEOWNERS` so they always receive a security review.
- **Lint**: `scripts/cedar-lint.sh` checks rendered and raw policies against the rule set documented in the script (L1-L7); `scripts/test-cedar-lint.sh` proves each rule.
- **Golden files**: `tests/policy.tftest.hcl` asserts the rendered Cedar for each scenario against `tests/golden/*.cedar`, so a change in policy semantics is visible in the diff.

## Update Documentation

The `terraform-docs` utility is used to generate this README. Follow the below steps to update:

1. Make changes to the `.terraform-docs.yml` file
2. Fetch the `terraform-docs` binary (https://terraform-docs.io/user-guide/installation/)
3. Run `terraform-docs markdown table --output-file ${PWD}/README.md --output-mode inject .`

<!-- BEGIN_TF_DOCS -->
## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | The name of the Verified Access deployment, used to name and tag all resources, e.g. production | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The dedicated subnets for the Verified Access endpoint network interfaces, one per availability zone | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags to apply to all resources | `map(string)` | n/a | yes |
| <a name="input_user_trust_provider"></a> [user\_trust\_provider](#input\_user\_trust\_provider) | The user identity trust provider, IAM Identity Center or an OIDC identity provider | <pre>object({<br/>    ## The type of user trust provider (iam-identity-center, oidc)<br/>    type = string<br/>    ## The Cedar context key for the provider, used by both the trust provider and the rendered policies<br/>    policy_reference_name = optional(string, "idc")<br/>    ## Require a verified email address (IAM Identity Center only)<br/>    require_verified_email = optional(bool, true)<br/>    ## The OIDC settings, required when type is oidc<br/>    oidc = optional(object({<br/>      # The OIDC issuer identifier<br/>      issuer = string<br/>      # The OIDC authorization endpoint<br/>      authorization_endpoint = string<br/>      # The OIDC token endpoint<br/>      token_endpoint = string<br/>      # The OIDC user info endpoint<br/>      user_info_endpoint = string<br/>      # The OAuth client id; the secret is passed in oidc_client_secret<br/>      client_id = string<br/>      # The space delimited scopes; offline_access enables refresh tokens<br/>      scope = optional(string, "openid email groups offline_access")<br/>      # The public signing key endpoint, enables native application (Connectivity Client) access<br/>      public_signing_key_endpoint = optional(string, null)<br/>    }), null)<br/>  })</pre> | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC containing the dedicated Verified Access subnets, used for the endpoint security groups | `string` | n/a | yes |
| <a name="input_access_logs"></a> [access\_logs](#input\_access\_logs) | Access logging configuration for the Verified Access instance; null disables logging (a check warns). Set for every live environment | <pre>object({<br/>    ## The OCSF log version (ocsf-0.1, ocsf-1.0.0-rc.2); rc.2 is required for trust context and TCP endpoints<br/>    log_version = optional(string, "ocsf-1.0.0-rc.2")<br/>    ## Include identity and device trust context in the logs; this is personal data, so it is opt-in<br/>    include_trust_context = optional(bool, false)<br/>    ## CloudWatch Logs destination; the module creates the log group so retention is always bounded<br/>    cloudwatch = optional(object({<br/>      # The log group name, defaults to /aws/verified-access/<name><br/>      log_group_name = optional(string, null)<br/>      # The number of days to retain the logs<br/>      retention_in_days = optional(number, 90)<br/>      # An optional customer managed KMS key used to encrypt the log group<br/>      kms_key_arn = optional(string, null)<br/>      # Create log derived metric filters and saved Logs Insights queries<br/>      enable_metric_filters = optional(bool, true)<br/>    }), null)<br/>    ## S3 destination; the bucket is owned elsewhere (e.g. log archive) and carries its own retention and object lock<br/>    s3 = optional(object({<br/>      # The name of the bucket<br/>      bucket_name = string<br/>      # The account id that owns the bucket, required when the bucket is in another account<br/>      bucket_owner = optional(string, null)<br/>      # An optional prefix for the log objects<br/>      prefix = optional(string, null)<br/>    }), null)<br/>    ## Kinesis Data Firehose delivery stream name, e.g. for a third party SIEM<br/>    firehose_delivery_stream_name = optional(string, null)<br/>  })</pre> | `null` | no |
| <a name="input_allowed_egress_cidr_blocks"></a> [allowed\_egress\_cidr\_blocks](#input\_allowed\_egress\_cidr\_blocks) | The CIDR blocks endpoint security groups may send traffic to when the target range cannot be derived (load-balancer, network-interface and rds endpoints) | `list(string)` | <pre>[<br/>  "10.0.0.0/8"<br/>]</pre> | no |
| <a name="input_cidr_endpoints_custom_subdomain"></a> [cidr\_endpoints\_custom\_subdomain](#input\_cidr\_endpoints\_custom\_subdomain) | An optional custom subdomain for CIDR endpoints; delegate it to the name servers exported by the module | `string` | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | The description of the Verified Access instance | `string` | `null` | no |
| <a name="input_device_trust_provider"></a> [device\_trust\_provider](#input\_device\_trust\_provider) | An optional device posture trust provider; null disables device posture | <pre>object({<br/>    ## The type of device trust provider (crowdstrike, jamf, jumpcloud)<br/>    type = string<br/>    ## The Cedar context key for the provider, defaults to the type, e.g. context.crowdstrike<br/>    policy_reference_name = optional(string, null)<br/>    ## The tenant id of the device provider application<br/>    tenant_id = string<br/>    ## CrowdStrike only: the minimum assessment.overall score (1-100) for sensitive endpoints<br/>    crowdstrike_min_score = optional(number, 50)<br/>    ## Jamf only: the risk levels permitted for sensitive endpoints<br/>    jamf_allowed_risk = optional(list(string), ["LOW", "SECURE"])<br/>  })</pre> | `null` | no |
| <a name="input_groups"></a> [groups](#input\_groups) | The Verified Access groups keyed by name; each group holds its access policy and the endpoints it protects | <pre>map(object({<br/>    ## The description of the group<br/>    description = optional(string, null)<br/>    ## The structured access policy (preferred), rendered to Cedar by the module<br/>    policy = optional(object({<br/>      # The identity groups permitted: Identity Center group ids, or OIDC group names<br/>      identity_groups = list(string)<br/>      # The team accountable for this access<br/>      owner = string<br/>      # Why this access exists<br/>      justification = string<br/>    }), null)<br/>    ## Escape hatch: a raw Cedar policy, e.g. file("policies/raw/<name>.cedar"); requires security review<br/>    raw_policy = optional(object({<br/>      # The Cedar policy text<br/>      cedar = string<br/>      # The team accountable for this access<br/>      owner = string<br/>      # Why the structured policy cannot express this access<br/>      justification = string<br/>    }), null)<br/>    ## The endpoints in this group keyed by name; names must be unique across all groups<br/>    endpoints = optional(map(object({<br/>      # The endpoint type (load-balancer, network-interface, cidr, rds)<br/>      type = string<br/>      # The description of the endpoint<br/>      description = optional(string, null)<br/>      # The protocol (http, https, tcp); cidr and rds endpoints are tcp only<br/>      protocol = optional(string, "tcp")<br/>      # Sensitive endpoints receive an endpoint policy requiring device posture<br/>      sensitive = optional(bool, false)<br/>      # The port for http/https and rds endpoints<br/>      port = optional(number, null)<br/>      # The port ranges for tcp endpoints<br/>      port_ranges = optional(list(object({<br/>        from_port = number<br/>        to_port   = number<br/>      })), [])<br/>      # The load balancer arn (load-balancer endpoints)<br/>      load_balancer_arn = optional(string, null)<br/>      # The network interface id (network-interface endpoints)<br/>      network_interface_id = optional(string, null)<br/>      # The CIDR block (cidr endpoints)<br/>      cidr = optional(string, null)<br/>      # The RDS target (rds endpoints); set exactly one of the arns<br/>      rds = optional(object({<br/>        instance_arn = optional(string, null)<br/>        cluster_arn  = optional(string, null)<br/>        proxy_arn    = optional(string, null)<br/>        endpoint     = string<br/>      }), null)<br/>      # The public DNS name users browse to (http/https endpoints only)<br/>      application_domain = optional(string, null)<br/>      # The public ACM certificate for the application domain (http/https endpoints only)<br/>      domain_certificate_arn = optional(string, null)<br/>      # The prefix for the generated endpoint domain, defaults to the endpoint name<br/>      endpoint_domain_prefix = optional(string, null)<br/>      # Override the subnets for this endpoint, defaults to var.subnet_ids<br/>      subnet_ids = optional(list(string), null)<br/>      # Additional security groups to attach to the endpoint<br/>      security_group_ids = optional(list(string), [])<br/>      # Override the CIDR blocks the endpoint security group may send to<br/>      egress_cidr_blocks = optional(list(string), null)<br/>      # Escape hatch: a raw Cedar endpoint policy; requires security review<br/>      raw_policy = optional(object({<br/>        cedar         = string<br/>        owner         = string<br/>        justification = string<br/>      }), null)<br/>    })), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | An optional customer managed KMS key used to encrypt Verified Access trust providers, groups and endpoints | `string` | `null` | no |
| <a name="input_oidc_client_secret"></a> [oidc\_client\_secret](#input\_oidc\_client\_secret) | The OAuth client secret for an OIDC user trust provider; source it from a secret store, never from tfvars | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_log_group_name"></a> [access\_log\_group\_name](#output\_access\_log\_group\_name) | The name of the CloudWatch log group receiving the access logs, when enabled |
| <a name="output_device_trust_provider_id"></a> [device\_trust\_provider\_id](#output\_device\_trust\_provider\_id) | The id of the device trust provider, when configured |
| <a name="output_endpoint_domains"></a> [endpoint\_domains](#output\_endpoint\_domains) | A map of endpoint name to the DNS name generated by Verified Access i.e. demo-ssh => edge-xxx.vai-xxx.prod.verified-access.eu-west-2.amazonaws.com |
| <a name="output_endpoint_ids"></a> [endpoint\_ids](#output\_endpoint\_ids) | A map of endpoint name to Verified Access endpoint id |
| <a name="output_endpoint_security_group_ids"></a> [endpoint\_security\_group\_ids](#output\_endpoint\_security\_group\_ids) | A map of endpoint name to the security group attached to its network interfaces; targets must allow traffic from the endpoint subnets |
| <a name="output_group_ids"></a> [group\_ids](#output\_group\_ids) | A map of group name to Verified Access group id |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | The id of the Verified Access instance |
| <a name="output_metric_namespace"></a> [metric\_namespace](#output\_metric\_namespace) | The CloudWatch namespace of the log derived metrics (AccessAllowed, AccessDenied, Http504, Http5xx), when enabled |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | The name servers of the instance, used to delegate cidr\_endpoints\_custom\_subdomain |
| <a name="output_rendered_policies"></a> [rendered\_policies](#output\_rendered\_policies) | A map of the rendered Cedar policies i.e. group/<name> and endpoint/<name> => policy; used for review, lint and golden tests |
| <a name="output_user_trust_provider_id"></a> [user\_trust\_provider\_id](#output\_user\_trust\_provider\_id) | The id of the user trust provider |
<!-- END_TF_DOCS -->
