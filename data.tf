## Find the current account, used to scope the alarm topic policy and to build the instance ARN
data "aws_caller_identity" "current" {}

## Find the current partition, used to build the instance ARN
data "aws_partition" "current" {}

## Find the current region, used to build the instance ARN and the dashboard widgets
data "aws_region" "current" {}

## Find the module subnets, whose ranges the endpoints and the central load balancer exchange traffic within
data "aws_subnet" "load_balancer" {
  count = local.enable_load_balancer ? length(var.subnet_ids) : 0

  id = var.subnet_ids[count.index]
}

## Find the subnets endpoints override; the module creates each endpoint's security group in var.vpc_id, so they must
## be in that VPC
data "aws_subnet" "endpoint" {
  for_each = toset(flatten([for endpoint in values(local.endpoints) : endpoint.subnet_ids != null ? endpoint.subnet_ids : []]))

  id = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = format("The subnet %s is in %s, but endpoint security groups are created in var.vpc_id (%s); endpoint subnet_ids must be in var.vpc_id.", self.id, self.vpc_id, var.vpc_id)
    }
  }
}
