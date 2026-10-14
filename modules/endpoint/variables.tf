variable "application_domain" {
  description = "The public DNS name users browse to (http and https endpoints only)"
  type        = string
  default     = null
}

variable "cidr" {
  description = "The CIDR block reached through the endpoint (cidr endpoints)"
  type        = string
  default     = null
}

variable "description" {
  description = "The description of the Verified Access endpoint"
  type        = string
  default     = null
}

variable "domain_certificate_arn" {
  description = "The public ACM certificate for the application domain (http and https endpoints only)"
  type        = string
  default     = null
}

variable "egress_cidr_blocks" {
  description = "The CIDR blocks the endpoint security group may send to; cidr endpoints always use their own CIDR"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "endpoint_domain_prefix" {
  description = "The prefix for the generated endpoint domain, defaults to the endpoint name"
  type        = string
  default     = null
}

variable "group_id" {
  description = "The id of the Verified Access group the endpoint belongs to"
  type        = string
}

variable "kms_key_arn" {
  description = "An optional customer managed KMS key used to encrypt the endpoint"
  type        = string
  default     = null
}

variable "load_balancer_arn" {
  description = "The internal load balancer reached through the endpoint (load-balancer endpoints)"
  type        = string
  default     = null
}

variable "name" {
  description = "The name of the Verified Access endpoint"
  type        = string
}

variable "network_interface_id" {
  description = "The network interface reached through the endpoint (network-interface endpoints)"
  type        = string
  default     = null
}

variable "policy_document" {
  description = "An optional rendered Cedar policy for the endpoint, evaluated in addition to the group policy"
  type        = string
  default     = null
}

variable "port" {
  description = "The port for http, https and rds endpoints"
  type        = number
  default     = null
}

variable "port_ranges" {
  description = "The port ranges for tcp endpoints"
  type = list(object({
    from_port = number
    to_port   = number
  }))
  default = []
}

variable "protocol" {
  description = "The protocol of the endpoint (http, https, tcp)"
  type        = string
  default     = "tcp"
}

variable "rds" {
  description = "The RDS target for rds endpoints; set exactly one of the arns"
  type = object({
    instance_arn = optional(string, null)
    cluster_arn  = optional(string, null)
    proxy_arn    = optional(string, null)
    endpoint     = string
  })
  default = null
}

variable "security_group_ids" {
  description = "Additional security groups to attach to the endpoint"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "The subnets for the endpoint network interfaces"
  type        = list(string)
}

variable "tags" {
  description = "The tags to apply to all resources"
  type        = map(string)
}

variable "type" {
  description = "The type of endpoint (load-balancer, network-interface, cidr, rds)"
  type        = string

  validation {
    condition     = contains(["load-balancer", "network-interface", "cidr", "rds"], var.type)
    error_message = "The type must be load-balancer, network-interface, cidr or rds."
  }
}

variable "vpc_id" {
  description = "The VPC holding the endpoint subnets, used for the endpoint security group"
  type        = string
}
