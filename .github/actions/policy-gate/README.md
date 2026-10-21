# Verified Access Policy Gate GitHub Action

A composite GitHub Action that checks the Cedar access policies of a Verified Access deployment: that the policies the module renders match the reviewed copies in the repository, and that they pass the module's lint rules and the official [Cedar CLI](https://github.com/cedar-policy/cedar).

The lint script comes from the same module version as the action (`@<ref>`), so the rules always match the module that renders the policies.

## Inputs

| Input                 | Required | Default    | Description                                                                                                          |
| --------------------- | -------- | ---------- | -------------------------------------------------------------------------------------------------------------------- |
| `paths`               | No       | `policies` | Newline-separated list of Cedar policy files or directories to lint.                                                 |
| `require-parser`      | No       | `true`     | Fail when the Cedar CLI cannot parse a policy (lint rule L1), rather than skipping the parse.                        |
| `cedar-version`       | No       | `4.13.0`   | Cedar CLI version used to parse the policies.                                                                        |
| `terraform-test-args` | No       | _(empty)_  | When set, runs `terraform init` and `terraform test` with these arguments first, e.g. `-var-file=values/production.tfvars`. |
| `terraform-version`   | No       | `1.14.5`   | Terraform version used with `terraform-test-args`.                                                                   |
| `working-directory`   | No       | `.`        | Directory holding the deployment (Terraform root and policies).                                                     |

## What gets checked

| Step                        | When                          | Fails when                                                                                       |
| --------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------ |
| Rendered policies match     | `terraform-test-args` is set  | The policies the module would apply differ from the reviewed copies (the deployment's own test) |
| Lint rules L1 to L9         | Always                        | A policy does not parse, has an unscoped permit, lacks an owner or justification, and so on ([rules](../../../docs/policies.md#lint-rules)) |

## Usage

### Deployment repository: gate the plan on the policies

```yaml
jobs:
  policy-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Verified Access policy gate
        uses: appvia/terraform-aws-verified-access/.github/actions/policy-gate@v0.1.0
        with:
          paths: policies
          terraform-test-args: -var-file=values/production.tfvars

  terraform:
    needs: policy-gate
    # ... the usual plan and apply workflow
```

### Lint only

```yaml
- uses: appvia/terraform-aws-verified-access/.github/actions/policy-gate@v0.1.0
  with:
    paths: |
      policies
      policies/raw
```

Pin `@<ref>` to the same module version the deployment uses.
