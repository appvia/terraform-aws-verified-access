# 0002: Tenant services are reached through a central NLB, not CIDR endpoints

- **Status:** Accepted (2026-10-15), proven for SSH and HTTPS; amended (2026-10-16): the NLB moved into the module as an option
- **Deciders:** platform team

## Context

Endpoints live in the network account ([ADR 0001](0001-endpoints-in-network-account.md)); tenant services live in spoke VPCs behind the transit gateway. Load-balancer endpoints must be in the same VPC as their load balancer. Network CIDR endpoints looked like a direct route for SSH and RDP, but in testing a CIDR endpoint targeting a tenant address across the transit gateway was **rejected** (`InvalidParameterValue: Invalid value for parameter cidr in CidrOptions`): Verified Access discovers the resources in the range, which it can only do inside its own VPC. AWS does not document this.

## Decision

An **internal NLB in the network account**, in the same subnets as the endpoints, with a listener per application and **IP targets** in tenant VPCs (availability zone `all`). Every tenant service is a `load-balancer` endpoint: TCP for SSH, RDP and databases; HTTP for web applications.

**Update (2026-10-16): the NLB is a module option.** It was first built in the deployment repository, next to the module. It now lives in the module behind `topology = "hub"`: each endpoint lists its service addresses in `targets`, and the module creates the listener, the target group, the registrations and the security group rules, and points the endpoint at the NLB. Reasons:

- **Self-service:** every hub-and-spoke customer needs the same NLB, so building it per deployment repeated the same code and review; one module block of values and toggles is enough.
- **Consistency:** the NLB, its security group and the endpoint egress rules are derived from the same input, so they cannot drift apart (one port per endpoint, targets as `/32` rules, endpoint subnets as the only source).
- **Validation at plan time:** duplicate listener ports, non IPv4 targets, target group names over 32 characters and `targets` without `topology = "hub"` are rejected before anything is applied.

`topology = "single-vpc"` (the default) creates no NLB, and an endpoint can still bring its own load balancer with `load_balancer_arn`.

## Consequences

- One NLB serves TCP and HTTP endpoints (HTTP endpoints work through an NLB; no ALB needed).
- About $20 a month, shared by all applications; up to 50 listeners per NLB.
- Each application needs its own listener port on the NLB.
- Tenant IP addresses are configuration (`targets`, known at plan time); in production, target the fixed private IPs of the tenant's own internal NLB so tenant changes do not need a platform change.
- Target group names are limited to 32 characters and unique per account and region, so they are `verified-access-<hash of name/endpoint>`, with the readable name in the `Name` tag: unique across deployments, no length rule on endpoint names, and within the `verified-access-*` prefix pipeline roles are scoped to.
- Health checks cross the transit gateway, which gives per application health alarms for free.

## Alternatives rejected

- **CIDR endpoints:** do not reach across the transit gateway.
- **Endpoints in tenant VPCs:** needs groups shared to tenants (rejected in ADR 0001).
- **ALB:** HTTP only; the NLB covers both.
