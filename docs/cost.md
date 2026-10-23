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
| Alarms (module option `alarms`) | about $0.10 per standard alarm a month; SNS email is free at these volumes | **under $1** (4 alarms, plus 2 per endpoint with `targets`) |
| Dashboard (module option `dashboard`) | $3 per dashboard a month beyond the free tier | **about $3** |
| Metric stream (module option `metric_stream`) | $0.003 per 1,000 metric updates, plus the Firehose delivery stream | A few dollars at these metric counts |
| AWS WAF (module option `waf`, created web ACL) | $5 per web ACL plus $1 per rule group a month, plus $0.60 per million requests | **about $8**, plus requests |

## Comparing with per user jump boxes

**Savings at a glance** for the [worked example](#worked-example-a-small-team-assumed-numbers) below: 5 users on $1,500 a month of hosted desktops used as jump boxes, reaching 3 servers and 2 internal websites.

| Setup | Verified Access per month | Saving per month | Saving per year |
| --- | --- | --- | --- |
| Websites on their own subdomains (one endpoint each) | about $862 | **about $640 (43%)** | **about $7,700** |
| Websites as paths of one hostname ([one endpoint and an ALB](#several-web-applications-subdomains-or-paths)) | about $685 | **about $815 (54%)** | **about $9,800** |

It stays cheaper up to about 10 servers, or a mix such as 4 servers and 4 websites; adding users never adds to the Verified Access side.

Many estates reach private systems through a hosted desktop per user (for example Amazon WorkSpaces used as a jump box). The two are priced on different axes, so the comparison is a **break-even model**, not a single answer:

| | Priced per | Grows when |
| --- | --- | --- |
| Per user jump box | **User** (always on or hourly, bundle dependent) | People are added |
| Verified Access | **Application** (endpoint hour), any number of users | Applications are added |

**The model** (monthly, list prices above):

```text
Verified Access  = 146 x TCP applications + 197 x web applications + 20 (shared NLB) + options
Jump boxes       = users x price per user
Break-even users = Verified Access / price per user
```

Above the break-even number of users, Verified Access costs less for that set of applications; below it, the jump boxes do.

### Break-even at a glance

Users needed for Verified Access to cost the same as jump boxes, for three per user prices (replace with the customer's bundle price):

| Applications behind the jump boxes | Verified Access per month | at $25 a user | at $35 a user | at $45 a user |
| --- | --- | --- | --- | --- |
| 1 TCP (for example SSH to a host group) | $166 | 7 | 5 | 4 |
| 1 TCP + 1 web | $363 | 15 | 11 | 9 |
| 5 TCP | $750 | 30 | 22 | 17 |
| 5 TCP + 5 web | $1,735 | 70 | 50 | 39 |

### Working it from a current spend

Start from what the customer spends today and ask what the same money buys:

1. **Current spend** on jump boxes, for example **$2,000 a month**.
2. **Users**: spend / price per user, for example $2,000 / $40 = **50 users**.
3. **Applications those users reach** through the jump boxes (only those used as a hop; desktops used for real work stay).
4. **Verified Access for those applications**, from the model above.

For the example $2,000 a month, the same budget covers about **13 TCP applications** or **10 web applications** ((2,000 - 20) / 146 and / 197), for any number of users. If the jump boxes front fewer applications than that, Verified Access costs less; if more, it costs more on infrastructure alone.

### Worked example: a small team (assumed numbers)

Customers rarely know their application count up front, so start from a stated assumption and adjust it once the inventory is done. Illustrative numbers for a typical small team:

| Assumption | Value |
| --- | --- |
| Hosted desktops used as jump boxes (RDP and SSH to servers, internal websites) | **$1,500 a month** |
| Users | about 5 (about $300 each) |
| Servers reached over RDP or SSH | **3** (assumed) |
| Internal websites | **2** (assumed) |

With `topology = "hub"`, each server is its own endpoint behind the central load balancer:

| Item | Per month |
| --- | --- |
| 3 servers x $146 | $438 |
| 2 websites x $197 | $394 |
| Central load balancer | $20 |
| Logs, alarms, dashboard | about $10 |
| **Verified Access** | **about $862** |
| Jump boxes today | $1,500 |
| **Difference** | **about $640 a month less (about $7,700 a year)** |

How the result moves when the assumption is wrong:

| Servers + websites | Verified Access per month | Against $1,500 |
| --- | --- | --- |
| 1 + 1 | $373 | about $1,130 less |
| 2 + 2 | $716 | about $780 less |
| 3 + 2 (the assumption) | $862 | about $640 less |
| 4 + 4 | $1,402 | about the same |
| 5 + 5 | $1,745 | about $245 more |

The break-even is `146 x servers + 197 x websites` of about **$1,470** (the spend less the shared $30): up to about 10 servers, 7 websites, or a mix such as 4 and 4. The number of users does not change the Verified Access side; more users only make the jump boxes dearer.

### What the model leaves out

- **Operating effort** on both sides: desktop images, patching and licensing for jump boxes; pull request changes and the Connectivity Client rollout for Verified Access. Add the customer's own figures when known.
- **Other uses of the desktops**: a jump box that is also someone's working desktop is not fully replaced.
- **Pricing details**: hourly billing modes, regional uplift and committed discounts on either side. Check current prices before quoting.
- **Security value**, which is not priced: identity checked on every request, access scoped to one application instead of a network, a per user audit trail of every attempt, and no standing compute to attack or maintain.

### Against a bastion host

A shared bastion (for example a t3.small, about $15 to $20 a month) costs less on infrastructure than any Verified Access endpoint, because one bastion serves many applications. The case there rests on removing its operating effort (patching, hardening, key management, access reviews) and its broad network reach, not on infrastructure cost.

### Several web applications: subdomains or paths

An endpoint serves one hostname (AWS does not accept a wildcard such as `*.example.com` as an application domain), so a wildcard certificate saves certificates but not endpoints. How the applications are addressed decides the cost:

| Web applications | One subdomain each (`app.example.com`, `app1.example.com`) | Paths of one hostname (`tools.example.com/app`, `/app1`) |
| --- | --- | --- |
| 2 | $394 (2 endpoints) | about $217 (1 endpoint + internal ALB) |
| 5 | $985 | about $217 |
| 10 | $1,970 | about $217 |

- **Subdomains** ([example](../README.md#several-web-applications-on-one-domain)): one endpoint each, with its own groups and targets. Works with any application. This is what the module builds today.
- **Paths**: one endpoint in front of an internal ALB that routes each path to its targets, and one policy with a rule per path and group (for example `context.http_request.path like "/app1/*"`). Each application must work under a path prefix, and all of them share one hostname, sign-in and WAF. Bring your own ALB with `load_balancer_arn` and write the per path rules in `raw_policy`; a module built ALB is on the [roadmap](how-it-works.md#roadmap).

### Keeping the cost down

Cost grows with the **number of applications**, not users. Keep endpoints to what is actually needed, and group several ports of one service on one TCP endpoint (TCP endpoints accept port ranges).
