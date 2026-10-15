# Architecture

AWS Verified Access gives users access to private applications without a bastion host, a hosted workstation or a VPN. Each request is checked against the user's identity (and optionally their device) at the point of access, and every attempt is logged.

This page describes the recommended design for a hub-and-spoke landing zone, how traffic flows for each type of access, and why. The decisions that are expensive to reverse are recorded as [ADRs](adr/). The design has been proven end to end (SSH through the Connectivity Client and HTTPS in the browser, to services in spoke VPCs across a transit gateway).

## The three layers

| Layer | Where | Changed per customer? |
| --- | --- | --- |
| **Module** | `appvia/terraform-aws-verified-access` (this repository) | Never. Every customer specific value is an input |
| **Deployment** | One repository per customer, from `appvia/terraform-aws-pipeline-template` | Yes: accounts, VPC, central load balancer, alarms, the policy gate |
| **Values** | `values/<environment>.tfvars` in the deployment repository | Yes: who can reach what |

A feature that only makes sense for one customer's topology goes in the deployment repository, never the module.

## Where everything lives

```mermaid
flowchart LR
  subgraph Users
    U1[Engineer laptop<br/>Connectivity Client]
    U2[Browser]
  end
  subgraph IdC[Management account]
    IC[IAM Identity Center<br/>organisation instance]
  end
  subgraph Network[Network account]
    VA[Verified Access instance<br/>trust provider, groups, Cedar policies]
    subgraph Ingress[Ingress VPC, private subnets]
      EP[Verified Access endpoints]
      NLB[Central internal NLB<br/>listener per application]
    end
    LOGS[CloudWatch Logs<br/>metrics, alarms]
    TGW((Transit gateway))
  end
  subgraph Tenant[Tenant account]
    APP1[SSH / RDP host]
    APP2[Internal web application]
  end
  U1 & U2 -->|sign in| IC
  U1 & U2 --> VA --> EP --> NLB --> TGW --> APP1 & APP2
  VA -.->|every attempt| LOGS
```

| Component | Placement | Why |
| --- | --- | --- |
| Verified Access instance, trust providers, groups | Network account, one instance per environment | The platform team owns access ([ADR 0001](adr/0001-endpoints-in-network-account.md)); Identity Center must be an organisation instance in the same region |
| Verified Access endpoints | Network account, **dedicated subnets** (for example in the ingress VPC, or a dedicated VPC attached like the ingress VPC) | Tenants cannot create their own endpoints (the approval gate) |
| Central internal NLB | Network account, same subnets as the endpoints | Endpoints only reach load balancers and addresses in their own VPC; the NLB reaches tenants across the transit gateway with IP targets ([ADR 0002](adr/0002-central-nlb-for-tenant-services.md)) |
| Tenant services | Tenant accounts, private subnets, no public addresses | Unchanged; the tenant security group allows the endpoint subnets |
| Access logs, metrics, alarms | Network account, CloudWatch (production: plus S3 in the log archive account) | See [logging](logging.md) and [observability](observability.md) |

## Network design

A hub without inspection. **Addresses are examples.**

```mermaid
flowchart TB
  INET((Internet<br/>users))
  subgraph NET[Network account]
    VAI[Verified Access instance<br/>AWS managed, public]
    subgraph ING[Ingress VPC 10.10.0.0/21]
      subgraph AZA[AZ a, endpoint subnet 10.10.0.0/24]
        ENIA[Endpoint ENIs]
        NLBA[NLB node]
      end
      subgraph AZB[AZ b, endpoint subnet 10.10.1.0/24]
        ENIB[Endpoint ENIs]
        NLBB[NLB node]
      end
      subgraph AZC[AZ c, endpoint subnet 10.10.2.0/24]
        ENIC[Endpoint ENIs]
        NLBC[NLB node]
      end
      RT1[Private route table<br/>10.0.0.0/8 to transit gateway]
    end
    subgraph TGW[Transit gateway]
      TRT[Hub route table<br/>routes to every spoke<br/>incl. 10.50.0.0/21]
      SRT[Spoke route table<br/>routes to hub VPCs<br/>incl. 10.10.0.0/21]
    end
  end
  subgraph SBX[Tenant account]
    subgraph SPK[Spoke VPC 10.50.0.0/21]
      SSH[SSH host 10.50.0.10:22]
      WEB[Web server 10.50.0.20:80]
      RT2[Private route table<br/>10.0.0.0/8 to transit gateway]
    end
  end
  INET -->|TLS, client tunnel or HTTPS| VAI
  VAI --> ENIA & ENIB & ENIC
  ENIA & ENIB & ENIC -->|22, 80| NLBA & NLBB & NLBC
  NLBA & NLBB & NLBC --> RT1 --> TRT -->|10.50.0.0/21| SPK
  SPK -.->|return 10.10.0.0/21| SRT -.-> ING
```

| Hop | Route | Notes |
| --- | --- | --- |
| Endpoint to NLB | Local, inside the ingress VPC | Endpoints can only reach load balancers and addresses in their own VPC (finding F4) |
| NLB to tenant | Endpoint subnet route table `10.0.0.0/8` to the transit gateway; the hub attachment uses a route table with a route to every spoke | IP targets outside the VPC are registered with availability zone `all` |
| Tenant back to NLB | Spoke route table `10.0.0.0/8` to the transit gateway; the spoke attachment's route table has the hub VPC's range | Spokes cannot reach each other; they can reply to the ingress VPC |
| New spokes | Associated with the spoke route table and propagated into the hub route table | With auto acceptance and propagation, no hub change is needed to onboard a tenant |

### Security groups

Security groups cannot reference each other across a transit gateway, so the tenant side allows the **endpoint subnet ranges**.

```mermaid
flowchart LR
  subgraph NET[Network account, ingress VPC]
    SGE[Endpoint security group<br/>verified-access-NAME-APP<br/>in: none<br/>out: app port to the endpoint subnets]
    SGN[NLB security group<br/>verified-access-NAME-nlb<br/>in: app ports from the endpoint subnets<br/>out: app port to each target /32]
  end
  subgraph TEN[Tenant account, spoke VPC]
    SGT[Tenant security group<br/>in: app port from<br/>the endpoint subnets]
  end
  SGE -->|22 / 80| SGN -->|22 to 10.50.0.10<br/>80 to 10.50.0.20| SGT
```

Every rule is scoped to one port and one destination: an endpoint can only reach the load balancer on its application's port, and the load balancer can only reach the registered targets.

### With an inspection VPC

**Recommendation: inspect.** With a central network firewall, associate the transit gateway attachment of the VPC holding the endpoints and the NLB with the inspection route table, so traffic to tenants passes the firewall like any other east-west traffic: one setting in the connectivity configuration, no change to Verified Access. The firewall must allow the endpoint subnets to the tenant ports. This path is validated by routing analysis, not tested.

## Alongside the existing ingress path

Public services keep their existing path (for example CloudFront, AWS WAF, the network firewall and a shared public load balancer, then the transit gateway to the tenant). Verified Access is a **separate path for the workforce**, so it neither duplicates nor bypasses that path:

| | Public ingress | Verified Access |
| --- | --- | --- |
| Who | Anyone on the internet (customers, the public) | Signed in staff, per identity group |
| What | Public applications | Private administration and internal applications (SSH, RDP, databases, internal web tools) |
| Edge | CloudFront, WAF, public load balancer | Verified Access, with an internal NLB (no public load balancer, no public address on any tenant service) |
| Controls | WAF rules, firewall | Cedar policy per request, identity (and optionally device), plus the same firewall when inspection is in place |

Rules that keep them separate: never point a Verified Access endpoint at a public load balancer, and never expose an internal application publicly to make it reachable; use a Verified Access endpoint instead. For HTTP endpoints, Verified Access can also be associated with an AWS WAF web ACL if application layer filtering is needed.

## Traffic paths

### TCP (SSH, RDP, databases) through the Connectivity Client

```mermaid
sequenceDiagram
  autonumber
  participant L as Laptop (Connectivity Client)
  participant IC as IAM Identity Center
  participant VA as Verified Access
  participant N as Central NLB (network account)
  participant T as Tenant host (spoke VPC)
  L->>IC: Sign in (browser, PKCE)
  IC-->>L: Token
  L->>VA: TCP to demo-ssh.<instance>.verified-access... (IPv6, through the client tunnel)
  VA->>VA: Evaluate the group policy (and endpoint policy) against the user's groups
  alt allowed
    VA->>N: Forward on the listener port
    N->>T: IP target across the transit gateway
    T-->>L: SSH session
  else denied
    VA--xL: No connection (the client sees a timeout)
  end
  VA->>VA: Log Allow or Deny with the user and their groups
```

- The endpoint name resolves to an **IPv6 address only** and works only while the Connectivity Client is connected.
- The client is available for **macOS and Windows only**; it needs a configuration file exported from the instance (see the [runbook](runbook.md)).
- Proven: SSH from a laptop to a host in a spoke VPC.

### HTTP and HTTPS in the browser (no client)

Users always connect to Verified Access over **HTTPS**; Verified Access then talks to the application over HTTP or HTTPS (the endpoint `protocol`). Proving HTTPS to the user with HTTP to the application covers both.

```mermaid
sequenceDiagram
  autonumber
  participant B as Browser
  participant DNS as Application DNS (customer zone)
  participant VA as Verified Access
  participant IC as IAM Identity Center
  participant N as Central NLB
  participant W as Tenant web server
  B->>DNS: demo.<domain>
  DNS-->>B: CNAME to the endpoint domain
  B->>VA: HTTPS (public certificate for the application domain)
  VA-->>B: Redirect to sign in
  B->>IC: Sign in
  IC-->>B: Back to the application
  VA->>VA: Evaluate the policy
  VA->>N: HTTP to the listener port
  N->>W: IP target across the transit gateway
  W-->>B: Page
```

- Needs a **public ACM certificate** for the application domain in the network account, and a CNAME from the application domain to the endpoint domain in whichever DNS the customer runs. The module takes both as inputs and creates neither.
- HTTP endpoints work through the central **NLB** (a TCP listener); an ALB is not needed.
- Proven: a page served from a private instance in a spoke VPC, with no public address.

### Denied access

A user who signs in but is not in a permitted group is denied by the Cedar policy before any traffic reaches the load balancer. TCP clients see a timeout; browsers see a 403 page. The access log records the decision, the user and their groups, which is how a denial is investigated (see the [runbook](runbook.md)).

## Endpoint types in scope

| Type | Covers | In scope | Notes |
| --- | --- | --- | --- |
| `load-balancer` | Any tenant service, TCP or HTTP | **Yes, the default** | Fronts the central NLB, which reaches tenants across the transit gateway |
| `network-interface` | A service on an ENI in the network account | Supported | Same-VPC only, so rarely useful for tenants |
| `cidr` | SSH, RDP by address range | Supported, **not for tenants** | Only reaches addresses **inside the endpoint's own VPC**; a tenant address across the transit gateway is rejected (`InvalidParameterValue`). Use `load-balancer` instead |
| `rds` | RDS instances, clusters, proxies | Supported | Same-VPC behaviour unproven; tenant databases can be reached as TCP through the NLB |

## Trust providers

| Provider | Supported by the module | Notes |
| --- | --- | --- |
| IAM Identity Center | Yes (organisation instance, same region) | Proven in testing; the recommended choice where Identity Center is already the workforce directory |
| OIDC (Okta, Entra ID, Google and others) | Yes | Group names in the `groups` claim; add the `offline_access` scope for the Connectivity Client |
| Device: Jamf, CrowdStrike, JumpCloud | Yes, optional; `sensitive` endpoints require it (fail closed) | Untested. Device context for **TCP** endpoints is unconfirmed by AWS documentation (risk R1): test with the provider before marking TCP endpoints sensitive |

Identity group membership is the control. The verified email condition is **off by default**: IAM Identity Center can report `email.verified = false` for every user (for example when users are provisioned from an external directory), and requiring it then denies everyone. Turn it on only where the directory verifies emails ([ADR 0003](adr/0003-identity-center-groups-as-the-control.md)).

## Inspection (hub with a network firewall)

The design is the same with an inspection VPC: the hub VPC's transit gateway attachment decides whether the leg to the tenant is inspected. This path is validated by routing analysis only, not tested.

## Quotas and grouping

Default quotas per account and region (all adjustable): 5 instances, 10 groups, 15 trust providers, **50 endpoints**. One NLB supports 50 listeners.

| Tenants | Applications each | Endpoints | Within the default? |
| --- | --- | --- | --- |
| 10 | 2 | 20 | Yes |
| 25 | 2 | 50 | At the limit: raise the quota first |
| 50 | 3 | 150 | Raise the endpoint quota; add a second NLB (listeners) |

**Grouping strategy:** a group is a set of endpoints sharing one policy, so create groups per **audience** (for example platform engineers, tenant developers, support), not per tenant. Tenant specific rules go in endpoint policies. This keeps well within the 10 group limit as tenants grow.

## Requesting access

1. The tenant raises a service desk request: the service, its private address and port, and who needs access.
2. A platform engineer opens a pull request in the deployment repository: the endpoint, the load balancer target and the group, with the rendered Cedar in `policies/`.
3. The policy gate and plan run; the platform team reviews and merges; the pipeline applies.
4. The service desk ticket links the pull request, which is the audit trail. See the [approval gate](approval-gate.md).
