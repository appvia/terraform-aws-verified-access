
## Terraform >= 1.9 is required for validations that reference other variables
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    # tflint-ignore: terraform_unused_required_providers
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}
