# 0002: Tenant services are reached through a central NLB, not CIDR endpoints

- **Status:** Accepted (2026-10-15), proven for SSH and HTTPS
- **Deciders:** platform team

## Context

Endpoints live in the network account ([ADR 0001](0001-endpoints-in-network-account.md)); tenant services live in spoke VPCs behind the transit gateway. Load-balancer endpoints must be in the same VPC as their load balancer. Network CIDR endpoints looked like a direct route for SSH and RDP, but in testing a CIDR endpoint targeting a tenant address across the transit gateway was **rejected** (`InvalidParameterValue: Invalid value for parameter cidr in CidrOptions`): Verified Access discovers the resources in the range, which it can only do inside its own VPC. AWS does not document this.

## Decision

An **internal NLB in the network account**, in the same subnets as the endpoints, with a listener per application and **IP targets** in tenant VPCs (availability zone `all`). Every tenant service is a `load-balancer` endpoint: TCP for SSH, RDP and databases; HTTP for web applications. The NLB lives in the deployment repository, not the module.

## Consequences

- One NLB serves TCP and HTTP endpoints (HTTP endpoints work through an NLB; no ALB needed).
- About $20 a month, shared by all applications; up to 50 listeners per NLB.
- Each application needs its own listener port on the NLB.
- Tenant IP addresses are configuration; in production, target the tenant's own private load balancer so tenant changes do not need a platform change.
- Health checks cross the transit gateway, which gives per application health alarms for free.

## Alternatives rejected

- **CIDR endpoints:** do not reach across the transit gateway.
- **Endpoints in tenant VPCs:** needs groups shared to tenants (rejected in ADR 0001).
- **ALB:** HTTP only; the NLB covers both.
