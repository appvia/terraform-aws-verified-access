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
