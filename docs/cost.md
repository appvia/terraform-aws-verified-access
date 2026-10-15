# Cost

Prices are AWS list prices from the [Verified Access pricing page](https://aws.amazon.com/verified-access/pricing/) (published in US dollars, US regions); London is typically a few percent higher. Check current prices before quoting a customer.

## Verified Access

| Item | Price | Per month, running continuously (730 hours) |
| --- | --- | --- |
| **TCP endpoint** (SSH, RDP, databases) | $0.20 per endpoint hour; 100 connections per endpoint hour included, then $0.001 per connection | **about $146** per endpoint |
| **HTTP(S) application** | $0.27 per application hour (first 148,800 hours a month, then $0.20); $0.02 per GB processed | **about $197** per application, plus data |
| Instance, groups, trust providers | No charge of their own | $0 |

## Supporting infrastructure (shared)

| Item | Approximate price | Per month |
| --- | --- | --- |
| Central internal NLB | about $0.025 per hour, plus capacity units (tiny for access traffic) | **about $20, shared by every application** (one listener per application, up to 50) |
| Access logs in CloudWatch | Ingestion and storage per GB | A few dollars at access log volumes |
| Public ACM certificate (HTTPS) | Free | $0 |

## What it replaces

| Option | Infrastructure per month | Hidden costs |
| --- | --- | --- |
| **Bastion host** (for example t3.small, disk, per tenant or environment) | about $15 to $20, **shared by all the applications behind it** | Patching, hardening, monitoring, key management and access reviews; broad network reach (a bastion can reach far more than the task needs); a weak audit trail (who did what, per user) |
| **Hosted workstation** (for example Amazon WorkSpaces, per user) | about $25 to $45 per user (bundle and billing mode dependent) | Image management, patching, licensing; scales per user, not per application |
| **Verified Access** | about $146 per TCP endpoint or $197 per HTTP application, plus a shared NLB | Endpoint and policy changes through pull requests; the Connectivity Client on macOS and Windows |

## Worked comparison

Assumptions (illustrative; replace with the customer's numbers): an engineer hour costs $75; a bastion takes 4 hours a month to patch, monitor and review; each tenant has one bastion in front of its applications.

| Estate | Bastions | Verified Access |
| --- | --- | --- |
| 1 tenant, 2 applications (SSH + web) | $18 + 4 h x $75 = **$318** | $146 + $197 + $20 NLB = **$363** |
| 10 tenants, 2 applications each | 10 x $318 = **$3,180** | 10 x $343 + $20 = **$3,450** |
| 10 tenants, 2 TCP applications each | **$3,180** | 20 x $146 + $20 = **$2,940** |

**Reading the numbers:**

- On infrastructure alone, Verified Access costs **more** than a bastion, because it is priced **per application** while one bastion serves many.
- Once the operating effort of standing compute is counted, the two are close; Verified Access wins where bastions need regular patching and access reviews, and where applications are mostly TCP.
- The case for Verified Access is mainly **not** cost: per request identity checks (and device posture where available), access scoped to one application instead of a network, a per user audit trail of every attempt, and no standing compute to attack or maintain.
- Cost grows with the **number of applications**, so keep endpoints to what is actually needed, and group several ports of one service on one endpoint (TCP endpoints accept port ranges).

## The spike itself

Running the demonstration (two endpoints, the NLB, a transit gateway attachment and two small instances) costs about $0.55 an hour, about $13 a day. Torn down after the demonstration.
