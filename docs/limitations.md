# Limitations

What to know before choosing Verified Access, and what the design around it implies. Workarounds are noted where they exist.

## Verified Access itself

These are properties of the AWS service; the module cannot change them.

| Limitation | Impact | Workaround |
| --- | --- | --- |
| **No Linux Connectivity Client** (macOS and Windows only) | Linux users cannot use TCP endpoints (SSH, RDP, databases) | Another access route for Linux users, or a supported desktop |
| **No CloudWatch metrics of its own** | Every metric is derived from the access logs, which arrive about 3 to 5 minutes after the attempt, so alarms lag | Log derived metrics and alarms ([observability](observability.md)) |
| **Policy changes take about 5 to 10 minutes** to take effect | Granting and revoking access is not instant, including in an emergency | Plan for the delay in the access request process |
| **A new endpoint takes about 17 minutes** to become active | Onboarding an application is slow to apply | Batch onboarding; the pipeline waits |
| **HTTP requests longer than 60 seconds** return 504 | Long running web requests fail | Change the application, or keep it on another route |
| **TCP and HTTP only** (no UDP) | Some protocols are not supported | Another route |
| **TCP endpoint names resolve to IPv6 only** and work only while the Connectivity Client is connected | "Could not resolve hostname" when the client is disconnected | Documented in the [runbook](runbook.md) |
| **A denied TCP connection looks like a timeout** to the user | Users cannot tell denied from broken | Check the access logs (`denied-requests` query) |
| **Priced per application** (about $146 a month per TCP endpoint, $197 per HTTP application) | Cost grows with the number of applications, unlike one shared bastion | Keep endpoints to what is needed; several ports of one service on one TCP endpoint ([cost](cost.md)) |
| **Quotas** per account and region: 50 endpoints, 10 groups, 5 instances, 15 trust providers (adjustable) | Large estates need quota increases | Group by audience, not tenant ([architecture](architecture.md#quotas-and-grouping)) |
| **For people, not automation** | Jobs that used a bastion need another route | AWS Systems Manager, PrivateLink or pipeline roles |
| **Permissions are under documented** | Creating an endpoint needs `sso:PutApplicationAssignmentConfiguration`, missing from AWS's documented permissions; exporting the client configuration needs `ec2:ExportVerifiedAccessInstanceClientConfiguration` | Grant the Identity Center application configuration actions to the deploying role; export the configuration with the pipeline role |

## Consequences of the design

These follow from placing Verified Access centrally in a hub-and-spoke network ([architecture](architecture.md)).

| Limitation | Impact | Workaround |
| --- | --- | --- |
| **Endpoints only reach their own VPC**; a `cidr` endpoint cannot target an address across a transit gateway | Every service in a spoke needs the **central NLB**: an extra hop and component | One shared NLB ([ADR 0002](adr/0002-central-nlb-for-tenant-services.md)); single VPC estates do not need it |
| **One NLB listener port per application**, up to 50 per NLB | Port planning; a second NLB beyond 50 applications | Allocate ports per application; add NLBs as needed |
| **NLB targets are fixed IP addresses** | A changed tenant address needs a platform change | Target the tenant's own private load balancer, whose addresses are stable |
| **HTTPS needs a public certificate and DNS** for each domain, in the network account, validated wherever the domain is hosted | The DNS owner is involved once per domain | One wildcard certificate per environment domain |
| **Access depends on the identity provider and Verified Access** | If either is unavailable, nobody gets in | Keep a documented break glass route (for example Systems Manager Session Manager with approval) |
| **Idle TCP sessions drop** after the load balancer idle timeout (350 seconds) | SSH sessions disconnect when idle | SSH keep alives (`ServerAliveInterval 60`) or a longer listener idle timeout |

## Not yet proven

| Item | Status |
| --- | --- |
| Device posture (Jamf, CrowdStrike, JumpCloud) on **TCP** endpoints | Not confirmed by AWS documentation; test with the provider before marking TCP endpoints `sensitive` |
| Whether revoking access ends an **active** session | New connections are denied after a revoke; active sessions untested |
| The path through an inspection VPC | Designed, validated by routing analysis only |
| `rds` endpoints | Supported, untested |
