locals {
  ## Indicates the endpoint uses port ranges (tcp) rather than a single port
  enable_port_ranges = var.type != "rds" && var.protocol == "tcp"
  ## The CIDR blocks the endpoint may send to; a cidr endpoint is scoped to exactly its own range
  egress_cidr_blocks = var.type == "cidr" ? [var.cidr] : var.egress_cidr_blocks
  ## The port ranges the endpoint may send to
  egress_ports = local.enable_port_ranges ? var.port_ranges : [{ from_port = var.port, to_port = var.port }]
  ## One egress rule per destination CIDR and port range
  egress_rules = {
    for pair in setproduct(local.egress_cidr_blocks, local.egress_ports) :
    format("%s-%d-%d", pair[0], pair[1].from_port, pair[1].to_port) => {
      cidr_ipv4 = pair[0]
      from_port = pair[1].from_port
      to_port   = pair[1].to_port
    }
  }
}
