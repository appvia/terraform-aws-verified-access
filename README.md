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

## Update Documentation

The `terraform-docs` utility is used to generate this README. Follow the below steps to update:

1. Make changes to the `.terraform-docs.yml` file
2. Fetch the `terraform-docs` binary (https://terraform-docs.io/user-guide/installation/)
3. Run `terraform-docs markdown table --output-file ${PWD}/README.md --output-mode inject .`

<!-- BEGIN_TF_DOCS -->
## Providers

No providers.

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->
