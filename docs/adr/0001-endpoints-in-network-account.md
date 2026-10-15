# 0001: Verified Access is owned by the platform team in the network account

- **Status:** Accepted (2026-10-14), proven 2026-10-15
- **Deciders:** platform team

## Context

Access must follow a two stage model: a tenant provisions its service, and only the platform team wires up access to it. A tenant must not be able to expose its own service. Verified Access groups can be shared to other accounts with AWS RAM, which would let tenants create endpoints themselves.

## Decision

One Verified Access instance per environment, with its trust providers, groups, endpoints and policies, in the **network account**. Groups are **not** shared to tenant accounts. Every change goes through the platform owned deployment repository.

## Consequences

- Tenants cannot create endpoints; the pull request is the approval gate ([approval gate](../approval-gate.md)).
- Endpoints sit away from tenant services, so a way across the transit gateway is needed ([ADR 0002](0002-central-nlb-for-tenant-services.md)).
- The 50 endpoint quota per account and region is shared by all tenants (adjustable).
- IAM Identity Center must be the organisation instance in the same region (it is).

## Alternatives rejected

- **Instance per tenant account, or groups shared through RAM:** tenants could expose services unilaterally; quotas and policies are scattered.
