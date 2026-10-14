<!-- markdownlint-disable -->
<a href="https://www.appvia.io/"><img src="https://github.com/appvia/terraform-aws-module-template/blob/main/docs/banner.jpg?raw=true" alt="Appvia Banner"/></a><br/><p align="right"> <a href="https://registry.terraform.io/modules/appvia/module-template/aws/latest"><img src="https://img.shields.io/static/v1?label=APPVIA&message=Terraform%20Registry&color=191970&style=for-the-badge" alt="Terraform Registry"/></a></a> <a href="https://github.com/appvia/terraform-aws-module-template/releases/latest"><img src="https://img.shields.io/github/release/appvia/terraform-aws-module-template.svg?style=for-the-badge&color=006400" alt="Latest Release"/></a> <a href="https://appvia-community.slack.com/join/shared_invite/zt-1s7i7xy85-T155drryqU56emm09ojMVA#/shared-invite/email"><img src="https://img.shields.io/badge/Slack-Join%20Community-purple?style=for-the-badge&logo=slack" alt="Slack Community"/></a> <a href="https://github.com/appvia/terraform-aws-module-template/graphs/contributors"><img src="https://img.shields.io/github/contributors/appvia/terraform-aws-module-template.svg?style=for-the-badge&color=FF8C00" alt="Contributors"/></a>

<!-- markdownlint-restore -->
<!--
  ***** CAUTION: DO NOT EDIT ABOVE THIS LINE ******
-->

![Github Actions](https://github.com/appvia/terraform-aws-module-template/actions/workflows/terraform.yml/badge.svg)

# Terraform AWS Module Template

A GitHub template repository for bootstrapping new [Terraform AWS modules](https://developer.hashicorp.com/terraform/language/modules) within the [Appvia](https://www.appvia.io/) organization. Use it to create consistent, production-ready modules with shared CI/CD, documentation, linting, and release tooling already in place.

This repository is the **source template**, not a module you deploy directly. After creating a new repository from it, you add your AWS resources, variables, and outputs, then publish the result to the [Terraform Registry](https://registry.terraform.io/) under the `appvia/<name>/aws` namespace.

## What's included

| Area | Details |
| --- | --- |
| **Module layout** | Root module with provider constraints (`terraform.tf`), plus an `examples/basic/` directory for integration-style usage |
| **CI/CD** | Reusable workflows from [appvia-cicd-workflows](https://github.com/appvia/appvia-cicd-workflows) for validation, workflow linting, and semver releases |
| **Local tooling** | `Makefile` targets for init, validate, test, lint, security scan, format, and docs generation |
| **Quality gates** | [tflint](https://github.com/terraform-linters/tflint) with AWS rules, [Trivy](https://trivy.dev/) config scanning, and [commitlint](https://commitlint.js.org/) for conventional commits |
| **Dependency updates** | [Renovate](https://docs.renovatebot.com/) with pinned GitHub Actions digests |
| **Changelog** | [git-cliff](https://git-cliff.org/) release notes generated on tag push |

## Getting started

### 1. Create a module repository

On GitHub, click **Use this template** and create a new repository named `terraform-aws-<service>` (for example, `terraform-aws-s3-bucket`).

### 2. Customize the module

After cloning your new repository:

1. Replace `<NAME>` placeholders in `README.md` with your module name (for example, `s3-bucket`).
2. Add your module implementation at the repository root:
   - `main.tf` — AWS resources and data sources
   - `variables.tf` — input variables with descriptions
   - `outputs.tf` — exported values
   - `versions.tf` or extend `terraform.tf` — provider and version constraints as needed
3. Implement `examples/basic/` as a working root module that invokes your module. Treat examples as reference implementations, not copy-paste root modules.
4. Add Terraform native tests (`.tftest.hcl`) if you need automated assertions.
5. Update `.template` metadata if your organization uses it for repository generation.

### 3. Validate locally

Install [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.0.7), [tflint](https://github.com/terraform-linters/tflint#installation), and [terraform-docs](https://terraform-docs.io/user-guide/installation/), then run:

```bash
make all
```

Common targets:

| Target | Purpose |
| --- | --- |
| `make init` | Initialize Terraform in the root module, examples, and submodules |
| `make validate` | Run `terraform validate` and commitlint against `main` |
| `make tests` | Run Terraform native tests |
| `make lint` | Run tflint and actionlint on workflows |
| `make security` | Run Trivy configuration scans |
| `make documentation` | Regenerate README and example docs via terraform-docs |

### 4. Release

Merge changes to `main` using [Conventional Commits](https://www.conventionalcommits.org/) (enforced by commitlint). Push a semver tag (for example, `v1.0.0`) to trigger the release workflow, which creates a GitHub Release and changelog via git-cliff.

Configure the new repository on the [Terraform Registry](https://registry.terraform.io/) so consumers can pin versions.

## Usage

Once you have published a module derived from this template, consumers reference it from the Terraform Registry:

```hcl
module "example" {
  source  = "appvia/<NAME>/aws"
  version = "~> 1.0"

  # Module-specific inputs
}
```

For local development or pre-release testing, use a path or Git source instead:

```hcl
module "example" {
  source = "git::https://github.com/appvia/terraform-aws-<NAME>.git?ref=v1.0.0"

  # Module-specific inputs
}
```

See `examples/basic/` for a starter layout. Copy the pattern, not the files verbatim — each example should reflect a realistic use case for your module.

## Repository structure

```text
.
├── .cliff/                 # git-cliff release configuration
├── .github/workflows/      # CI validation, release, and workflow checks
├── examples/
│   └── basic/              # Example root module invoking this module
├── terraform.tf            # Terraform and provider version constraints
├── Makefile                # Local development automation
├── .terraform-docs.yml     # terraform-docs configuration
├── .tflint.hcl             # tflint rules and plugins
├── renovate.json           # Renovate dependency update policy
└── README.md               # Module documentation (partially generated)
```

## Update documentation

Module inputs, outputs, and providers below are generated by [terraform-docs](https://terraform-docs.io/). After changing variables or outputs:

1. Adjust `.terraform-docs.yml` if you need different sections or formatting.
2. Run `make documentation`, or manually:

   ```bash
   terraform-docs markdown table --output-file README.md --output-mode inject .
   ```

Do not edit content between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` by hand.

<!-- BEGIN_TF_DOCS -->
## Providers

No providers.

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->
