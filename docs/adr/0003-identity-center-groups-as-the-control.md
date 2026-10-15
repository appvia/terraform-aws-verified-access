# 0003: Identity group membership is the access control

- **Status:** Accepted (2026-10-15); module default changed to match
- **Deciders:** platform team

## Context

The module supports IAM Identity Center and OIDC user trust providers, and optional device trust providers. It renders a verified email condition (`context.idc.user.email.verified == true`) by default. In testing, Identity Center reported `email.verified = false` for every user (common when users are provisioned from an external directory), so that condition denied everyone, including members of the permitted group.

## Decision

Access is decided by **identity group membership** (group IDs or names, sorted, in the rendered Cedar). The verified email condition is **off by default** (`require_verified_email = false`) and can be turned on where the directory verifies emails. Groups are created per audience, not per tenant.

## Consequences

- Access is managed where identities already are; joiners and leavers flow through Identity Center.
- The verified email condition adds nothing where the directory does not verify emails; customers whose directory does verify them can keep it.
- No device posture check: anyone in the group can connect from any device with the client. Customers with Jamf, CrowdStrike or JumpCloud can add it; device context for TCP endpoints must be tested first (risk R1).
- Customers who rely on verified emails must opt in.
