# Getting started

This guide takes you from nothing to engineers connecting to a private server over SSH and opening a private web application in their browser, without a bastion host. It assumes you know AWS but not Terraform; each Terraform term is explained the first time it appears.

If you want to know how the traffic flows, see [how it works](how-it-works.md). Day to day running is in [operations](operations.md), and approvals and logging are in [security](security.md).

## What you get

[AWS Verified Access](https://docs.aws.amazon.com/verified-access/latest/ug/what-is-verified-access.html) is an AWS managed front door for private applications. Before every connection it checks who the user is (through your identity provider, such as IAM Identity Center) and whether their group is allowed to reach that application. Every attempt, allowed or denied, is logged.

This repository is a **Terraform module**. Terraform is a tool that reads files describing the AWS resources you want, compares them with what exists, and creates or changes resources to match. A module is a reusable package of those descriptions: you fill in a handful of values and the module creates everything else. From one block of settings you get:

| What | What it is for |
| --- | --- |
| A Verified Access instance | The front door itself, one per environment |
| A trust provider | The link to your identity provider (IAM Identity Center or another OIDC provider) |
| Groups and access policies | Who may reach what. You list identity groups; the module writes the policy in [Cedar](https://www.cedarpolicy.com/), AWS's policy language |
| Endpoints | One per application: the address users connect to |
| A central network load balancer (optional) | Reaches applications in other VPCs across a transit gateway |
| Access logs | Every attempt, with the user and their groups, in CloudWatch Logs (and optionally S3 or Firehose) |
| A certificate, alarms, a dashboard, WAF, a metric stream (all optional) | Switched on one setting at a time |

Users reach **TCP** applications (SSH, RDP, databases) through the AWS Verified Access Connectivity Client on their laptop, and **web** applications in an ordinary browser.

## What you need before starting

### An AWS account, a VPC and subnets

- The **network account** (the AWS account that holds your shared networking) where Verified Access will live, and the region your IAM Identity Center is in.
- A **VPC** (virtual private cloud: your private network in AWS) for the endpoints, and **dedicated subnets** in it, one per availability zone. Small subnets are fine (the examples use `/27`). Note the VPC ID (`vpc-...`) and the subnet IDs (`subnet-...`) from the VPC console.
- If your applications are in **other VPCs** (spokes) connected by a **transit gateway**, you will use the hub topology. The routes must already let the endpoint subnets reach the spokes and the spokes reply ([network design](how-it-works.md#network-design)). Not sure? Read [do I need the central NLB?](how-it-works.md#do-i-need-the-central-nlb).
- The **private IP address and port** of each application, for example `10.50.0.10` port 22 for an SSH host and `10.50.0.20` port 80 for a web server.

### Identity Center group IDs

Access is given to **groups**, never to individual users. You need the ID of each IAM Identity Center group that should have access (with an OIDC provider, use the group names instead).

- **Console:** IAM Identity Center, then **Groups**, then select the group. The **Group ID** is shown in the group details and looks like `11111111-1111-1111-1111-111111111111`.
- **Command line:** find the identity store ID under IAM Identity Center **Settings** (it looks like `d-1234567890`), then:

  ```bash
  aws identitystore get-group-id \
    --identity-store-id d-1234567890 \
    --alternate-identifier '{"UniqueAttribute":{"AttributePath":"displayName","AttributeValue":"Engineers"}}'
  ```

Use the ID, not the display name: the module rejects names with Identity Center, because a name could be reused for a different group.

### A domain, for web applications only

Web applications are served on your own names, for example `tools.example.com`. You need a domain you control (`example.com`) and someone who can add DNS records to it. The module can request the certificate for you; you publish two kinds of DNS record by hand later, or, if the domain is a Route 53 public hosted zone, the module publishes them for you ([Route 53](#let-the-module-publish-the-dns-records)).

### A deployment repository and pipeline

You do not run Terraform from your laptop. Create a **deployment repository** from the template `appvia/terraform-aws-pipeline-template`. It contains the pipeline (GitHub Actions workflows) that runs Terraform for you:

- On a **pull request** it runs the policy gate and a **plan** (a dry run that lists what would change) with a read-only role.
- On **merge to `main`** it runs **apply** (makes the changes) with a read-write role.

The pipeline signs in to AWS with **OIDC**: GitHub proves to AWS which repository and branch is asking, and AWS lets it assume an IAM role, so no long-lived keys are stored. You need that **pipeline role** in the network account, trusting your deployment repository. Note its name (for example `verified-access-pipeline`). Besides the usual permissions, it needs `sso:PutApplicationAssignmentConfiguration` (missing from AWS's documented permissions) to create endpoints, and `ec2:ExportVerifiedAccessInstanceClientConfiguration` to export the client configuration.

Protect `main` with branch protection (code owner review required, gate and plan checks required, no bypass). The [approval gate](security.md#the-approval-gate) depends on it.

## The one file, line by line

Everything is one **module block**: a block of HCL (Terraform's configuration language) that names the module and gives it values. Some syntax first:

- `name = value` sets one setting. Text goes in quotes, numbers and `true`/`false` do not.
- `[ ... ]` is a list. `{ ... }` is a group of settings.
- An optional feature is **off** when you leave it out (or set it to `null`) and **on** when you set it. `dashboard = {}` means "on, with the default settings".
- `#` starts a comment, which Terraform ignores.

This is the whole configuration for a hub with one SSH application and one web application, a certificate, alarms, a dashboard and WAF:

```hcl
module "verified_access" {
  # Where Terraform downloads the module from (the public Terraform Registry), and which release.
  # Pin the version; change it on purpose to upgrade.
  source  = "appvia/verified-access/aws"
  version = "0.1.0"

  # A short name for this deployment, used in every resource name (verified-access-production).
  # Resources are named <name_prefix>-<name>-...; set name_prefix to follow your own
  # naming convention (default verified-access). With hub, prefix + name is at most 31 characters.
  name = "production"

  # The VPC and the dedicated subnets that hold the endpoints (and the central load balancer).
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  # "hub": the applications are in other VPCs behind a transit gateway, so the module creates a
  # central internal network load balancer to reach them. Use "single-vpc" (the default) when
  # the applications are in the same VPC as the endpoints.
  topology = "hub"

  # Labels added to every resource the module creates.
  tags = {
    Environment = "Production"
    Owner       = "platform-team"
  }

  # Who users sign in with. IAM Identity Center must be the organisation instance, in this region.
  user_trust_provider = {
    type = "iam-identity-center"
  }

  # Access logs: every attempt, allowed or denied. include_trust_context adds the user and their
  # groups, which you need to explain a denial (it is personal data, so it is off unless you set it).
  # cloudwatch = {} creates the log group /aws/verified-access/production, kept for 90 days.
  access_logs = {
    include_trust_context = true
    cloudwatch            = {}
  }

  # A wildcard certificate (*.example.com) for the web applications. Every web application name
  # must be one level below it, for example tools.example.com.
  certificate = {
    domain_name = "example.com"
  }

  # Alarms to a new SNS topic (verified-access-production-alarms), emailed to these addresses.
  # pipeline_role_name: any change to Verified Access made by anyone other than the pipeline raises
  # an alarm, so nobody can quietly bypass the pull request.
  alarms = {
    email_addresses    = ["platform-team@example.com"]
    pipeline_role_name = "verified-access-pipeline"
  }

  # A CloudWatch dashboard (verified-access-production), and a WAF web ACL with AWS managed rules
  # in front of the web applications.
  dashboard = {}
  waf       = { create = true }

  # Who may reach what. A group is an audience (here, platform engineers) with one policy and
  # the endpoints it protects.
  groups = {
    platform-engineers = {
      description = "Platform engineers administering tenant hosts and tools"

      policy = {
        # The Identity Center group IDs allowed in. Everyone else is denied.
        identity_groups = ["11111111-1111-1111-1111-111111111111"]
        # Who is accountable for this access, and why it exists (at least 10 characters).
        owner         = "platform-team"
        justification = "Platform engineers administer the tenant hosts and tools"
      }

      endpoints = {
        # An SSH host in a spoke VPC. Users connect with the Connectivity Client.
        hosts-ssh = {
          type        = "load-balancer"                   # through the central load balancer
          port_ranges = [{ from_port = 22, to_port = 22 }] # one port; it becomes the listener port
          targets     = ["10.50.0.10"]                     # the host's private IP address
        }

        # A web application in a spoke VPC. Users browse to https://tools.example.com.
        tools-web = {
          type               = "load-balancer"
          protocol           = "http"              # how Verified Access talks to the application;
          port               = 80                  # users always get HTTPS
          application_domain = "tools.example.com" # covered by the certificate above
          targets            = ["10.50.0.20"]
        }
      }
    }
  }
}
```

Each endpoint with `targets` needs its own listener port, because each gets its own listener on the central load balancer; two services on the same port (for example two SSH hosts) set `listener_port` ([several hosts on one port](#several-hosts-on-one-port)). Before you merge, the module checks many rules (for example an empty `identity_groups`, two endpoints on the same port, or a web domain the certificate does not cover) and stops the plan with a clear message.

Every option and its default is listed in the [README](../README.md) (inputs). The optional parts are summarised in the [options table](../README.md#options).

## Where the values come from

The deployment repository usually runs the same configuration in more than one environment (for example `staging` and `production`). So the module block refers to **variables** instead of fixed values, and each environment has a **values file** that sets them:

```text
values/production.tfvars  ->  variables.tf  ->  main.tf (the module block)
the actual values             declares each     uses them as var.<name>
for one environment           variable
```

`values/production.tfvars` sets the values for production (a `.tfvars` file is just `name = value` lines):

```hcl
name       = "production"
vpc_id     = "vpc-0123456789abcdef0"
subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

alarm_email_addresses = ["platform-team@example.com"]

groups = {
  platform-engineers = {
    description = "Platform engineers administering tenant hosts and tools"
    policy = {
      identity_groups = ["11111111-1111-1111-1111-111111111111"]
      owner           = "platform-team"
      justification   = "Platform engineers administer the tenant hosts and tools"
    }
    endpoints = {
      hosts-ssh = {
        type        = "load-balancer"
        port_ranges = [{ from_port = 22, to_port = 22 }]
        targets     = ["10.50.0.10"]
      }
      tools-web = {
        type               = "load-balancer"
        protocol           = "http"
        port               = 80
        application_domain = "tools.example.com"
        targets            = ["10.50.0.20"]
      }
    }
  }
}
```

`variables.tf` declares each variable: its name, its type and a description. `type = any` passes the structure through to the module, which checks it:

```hcl
variable "name" {
  description = "The name of the Verified Access deployment"
  type        = string
}

variable "groups" {
  description = "The Verified Access groups, their policies and endpoints"
  type        = any
}

# ... and the same for vpc_id, subnet_ids and alarm_email_addresses
```

`main.tf` holds the module block from the previous section, with `var.<name>` in place of the values that differ per environment:

```hcl
module "verified_access" {
  source  = "appvia/verified-access/aws"
  version = "0.1.0"

  name       = var.name
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
  topology   = "hub"
  # ... the settings that are the same everywhere stay as they are ...

  alarms = {
    email_addresses    = var.alarm_email_addresses
    pipeline_role_name = "verified-access-pipeline"
  }

  groups = var.groups
}
```

The pipeline gives Terraform the values file of the environment it is deploying (the same as `terraform plan -var-file=values/production.tfvars`). Day to day, almost every change is to `groups` in the values file. The deployment repository also keeps a reviewed copy of every rendered policy in `policies/` (see [step 1](#1-open-a-pull-request)).

## Your first deployment

### 1. Open a pull request

Put the module block in `main.tf`, the variables in `variables.tf` and the values in `values/production.tfvars`, on a new branch.

The module writes the Cedar policy for each group, and the deployment repository keeps a reviewed copy in `policies/` so reviewers see the exact effect of every change. Run `terraform test -var-file=values/production.tfvars` locally: the first time it fails and shows the rendered policy; save it to the matching file in `policies/` and run it again until it passes. Open the pull request.

### 2. Read the plan

The pipeline posts the plan as a comment on the pull request. A plan lists every resource Terraform would create (`+`), change in place (`~`), replace (`-/+`) or destroy (`-`), and ends with a count such as `Plan: 30 to add, 0 to change, 0 to destroy`. On a first deployment, check:

- **Only additions.** Nothing should be changed or destroyed on a first run.
- **The resources you expect:** a Verified Access instance, a trust provider, a group per entry in `groups`, an endpoint per application, the central load balancer with a listener and target group per endpoint, the log group, the certificate, the alarms, the dashboard and the web ACL.
- **The policy:** the group's policy lists the right group IDs and nothing else.
- **Names:** resources are named `verified-access-<name>...` with your deployment name.

If the plan stops with an error, the message says which rule was broken (for example "Endpoints with targets must use different ports"). Fix the values and push again.

### 3. Merge and apply

Get a code owner to review and approve, then merge. The pipeline runs apply on `main`. The endpoints take **about 17 minutes** to become active and the pipeline waits for them, so the run is slow; this is normal.

### 4. Publish the certificate validation records

Skip this step and the next if the module publishes the records in Route 53 (`dns`, see [Route 53](#let-the-module-publish-the-dns-records)).

AWS issues the certificate only after you prove you own the domain. Read the `certificate_validation_records` output from the apply (a map of record name to value) and create each one as a **CNAME** record in your domain's DNS. The certificate is issued a few minutes later. Details, including `certificate.wait_for_validation`, are in [operations](operations.md#publish-the-certificate-validation-records).

### 5. Point the application name at its endpoint

For each web application, create a **CNAME** record from its `application_domain` (`tools.example.com`) to its endpoint domain: the `application_domains` output maps each application domain to the name it must point at. SSH and other TCP applications need no DNS record: users connect to the endpoint domain itself.

### 6. Wait for the endpoints

If the apply finished, the endpoints are active. Allow about 17 minutes from the start of the apply if you are watching it.

### 7. Export the client configuration

The Connectivity Client needs a configuration file from the Verified Access instance (output `instance_id`; the `client_configuration_command` output is this command, ready to run):

```bash
aws ec2 export-verified-access-instance-client-configuration \
  --verified-access-instance-id <instance_id> > ClientConfig-production.json
```

This needs `ec2:ExportVerifiedAccessInstanceClientConfiguration`, which engineer and read-only roles often lack. A manual pipeline workflow using the pipeline role is a simple way to provide it. In production, distribute the file through your device management (MDM).

### 8. Install the Connectivity Client

Install the [AWS Verified Access Connectivity Client](https://docs.aws.amazon.com/verified-access/latest/ug/connectivity-client.html) on macOS or Windows (there is no Linux client), from the signed installer. Disconnect other VPNs and keep IPv6 enabled. Install the configuration file, owned by root (macOS):

```bash
sudo mkdir -p "/Library/Application Support/Connectivity Client"
sudo cp ClientConfig-*.json "/Library/Application Support/Connectivity Client/"
sudo chown root "/Library/Application Support/Connectivity Client/"ClientConfig-*.json
```

On Windows the file goes in `C:\ProgramData\Connectivity Client`.

### 9. Connect and test

- **SSH:** open the client and sign in, then connect to the endpoint domain from `endpoint_domains`, for example `ssh ec2-user@hosts-ssh.<instance>.prod.verified-access.<region>.amazonaws.com`. The name works only while the client is connected.
- **HTTPS:** browse to `https://tools.example.com`. You are sent to sign in, then back to the application. No client is needed.
- **A denial:** ask someone who is **not** in the group to try both. SSH times out (a denial looks like a timeout) and the browser shows a 403 page. Within 3 to 5 minutes both attempts appear in the `verified-access/production/denied-requests` saved query in CloudWatch Logs Insights, with the user and their groups.

Something not working? See [troubleshooting](operations.md#troubleshooting).

## Everyday tasks

Every change follows the same path: edit on a branch, open a pull request, read the plan, get a review, merge. When a change alters a policy, update the copy in `policies/` as in [step 1](#1-open-a-pull-request).

| Change | How long until it takes effect after the apply |
| --- | --- |
| Give or remove access | About 10 minutes (policy propagation, 5 to 10 minutes) |
| Add an application | About 17 minutes (new endpoint) |
| Change a target IP | As soon as the new target passes its load balancer health checks (a minute or two) |
| Change alarm thresholds or emails | Immediately; new email recipients must confirm the subscription first |
| Turn an option on or off | Immediately, except new endpoints (17 minutes) and certificates (once the DNS records are published) |

### Give or remove access

Add or remove an Identity Center group ID in `identity_groups`, in `values/production.tfvars`:

```hcl
    policy = {
      identity_groups = [
        "11111111-1111-1111-1111-111111111111",
        "22222222-2222-2222-2222-222222222222", # added: support engineers
      ]
```

To give one person access, add them to an existing group in IAM Identity Center instead: no pull request needed. Removing access is the same change in reverse, with the same delay of about 10 minutes, and new connections are denied after that (whether an active session is ended is untested). For a new audience, add a new entry under `groups` with its own `policy` and `endpoints`: groups are per audience (for example support), not per tenant. A worked example of the policy diff is in [security](security.md#a-worked-example).

### Add an application

1. The application's owner allows the **endpoint subnet ranges** on the application's port in its security group (security groups cannot reference each other across a transit gateway).
2. Add an endpoint under the right group, on a port no other endpoint uses:

   ```hcl
      endpoints = {
        # ... existing endpoints ...
        reports-db = {
          type        = "load-balancer"
          port_ranges = [{ from_port = 5432, to_port = 5432 }]
          targets     = ["10.50.0.30"]
        }
        wiki-web = {
          type               = "load-balancer"
          protocol           = "http"
          port               = 8080
          application_domain = "wiki.example.com"
          targets            = ["10.50.0.40"]
        }
      }
   ```

3. Web applications only: the name must be one level below the certificate's `domain_name`. After the apply, add the CNAME to its endpoint domain ([step 5](#5-point-the-application-name-at-its-endpoint)).

### Change a target IP

Edit `targets`:

```hcl
        hosts-ssh = {
          type        = "load-balancer"
          port_ranges = [{ from_port = 22, to_port = 22 }]
          targets     = ["10.50.0.11"] # was 10.50.0.10
        }
```

The plan shows the old target being deregistered and the new one registered. Where you can, target the fixed private IPs of the application's own internal load balancer, so changes behind it need no change here.

### Change alarm thresholds or emails

Edit the `alarms` block. Thresholds are optional; leave out any you do not change:

```hcl
  alarms = {
    email_addresses    = ["platform-team@example.com", "on-call@example.com"]
    pipeline_role_name = "verified-access-pipeline"
    thresholds = {
      access_denied           = 50 # denied requests in five minutes (default 20)
      http_504                = 5  # HTTP 504s in five minutes (default 5)
      logging_stopped_hours   = 1  # hours without access logs (default 1)
      no_access_allowed_hours = 72 # hours without a successful connection (default 24)
    }
  }
```

The alarms are described in [operations](operations.md#alarms).

### Several hosts on one port

Each endpoint with `targets` has its own listener on the central load balancer, and two listeners cannot share a port. To put several services on the same port behind it, for example SSH hosts that all listen on 22, give each endpoint a `listener_port`:

```hcl
        host-a-ssh = {
          type          = "load-balancer"
          port_ranges   = [{ from_port = 22, to_port = 22 }] # the port the host listens on
          targets       = ["10.50.0.10"]
          listener_port = 2201 # the port on the load balancer, and the port users connect to
        }
        host-b-ssh = {
          type          = "load-balancer"
          port_ranges   = [{ from_port = 22, to_port = 22 }]
          targets       = ["10.50.0.11"]
          listener_port = 2202
        }
```

Two ports matter, and they go to different places:

| Port | Set by | Used for |
| --- | --- | --- |
| **Listener port** | `listener_port` (defaults to the service port) | The listener on the central load balancer, the port the Verified Access endpoint is configured with, and therefore the port users connect to: `ssh -p 2201 ec2-user@<host-a-ssh endpoint domain>` |
| **Service port** | `port_ranges` (TCP) or `port` (HTTP) | The target group: the port the load balancer sends to on the host, and the port the host's security group must allow from the endpoint subnets |

For web applications users always browse on 443, so `listener_port` only changes the hop between Verified Access and the load balancer. A host that listens on a different port from the rest of its endpoint's targets can use `target_details = [{ ip = "10.50.0.12", port = 2222 }]` instead of `targets`. With `topology = "hub"` one load balancer holds at most 50 listeners, and its security group needs one inbound rule per listener and subnet range and one outbound rule per target address and port; the plan stops with a clear message before the default quota of 60 rules is exceeded.

### Let the module publish the DNS records

If the domain is a Route 53 public hosted zone in the same account, give the module the zone and it publishes the certificate validation records and a CNAME from each web application's `application_domain` to its endpoint domain. With `wait_for_validation`, the apply waits until the certificate is issued:

```hcl
  certificate = {
    domain_name         = "example.com"
    wait_for_validation = true
  }

  dns = {
    zone_id = "Z0123456789ABCDEFGHIJ" # Route 53 console, Hosted zones, the zone's Hosted zone ID
  }
```

`dns.create_validation_records = false` or `dns.create_application_records = false` leave either kind of record to you. The pipeline role then also needs `route53:ChangeResourceRecordSets`, `route53:GetChange`, `route53:GetHostedZone` and `route53:ListResourceRecordSets` on that zone.

### Tag for chargeback

`tags` applies to everything the module creates. To charge a tenant or cost centre for its applications, add `tags` to a group (applied to the group and all of its endpoints) or to an endpoint (overriding the group's for that endpoint). They are applied to the endpoint, its security group, and its target group and listener on the central load balancer:

```hcl
  groups = {
    tenant-a = {
      tags = { CostCentre = "tenant-a" }
      # ... policy ...
      endpoints = {
        reports-db = {
          # ... endpoint settings ...
          tags = { CostCentre = "tenant-a-reporting" } # overrides the group's for this endpoint
        }
      }
    }
  }
```

Activate the tag keys as cost allocation tags in the billing console to see them in Cost Explorer.

### Send alarms to PagerDuty or Slack

Alarms go to one SNS topic (the module's, or yours with `alarms.sns_topic_arn`). To page an on-call tool as well, subscribe it to an SNS topic of its own and add that topic to `alarms.additional_action_arns`: every alarm notifies it when it fires and when it recovers.

- **PagerDuty:** create an Amazon CloudWatch integration on the PagerDuty service, and subscribe its integration URL (HTTPS) to an SNS topic.
- **Slack or Microsoft Teams:** configure AWS Chatbot (Amazon Q Developer in chat applications) for the channel, with an SNS topic.

```hcl
  alarms = {
    email_addresses        = ["platform-team@example.com"]
    additional_action_arns = ["arn:aws:sns:eu-west-2:111111111111:pagerduty", "arn:aws:sns:eu-west-2:111111111111:slack-alerts"]
    disabled               = ["no-access-allowed"] # not useful in a quiet environment
  }
```

The change-outside-the-pipeline alarm (A7) is an EventBridge rule, which notifies only the main topic. Turning alarms off or changing their periods is in [operations](operations.md#customising-the-alarms).

### Turn options on or off

Set an option to turn it on; remove it (or set it to `null`) to turn it off.

| Option | On | Notes |
| --- | --- | --- |
| Central load balancer | `topology = "hub"` | Off is `"single-vpc"`; endpoints with `targets` need `hub` |
| Fixed load balancer addresses | `load_balancer = { private_ips = { "subnet-0123456789abcdef0" = "10.10.0.100", "subnet-0123456789abcdef1" = "10.10.1.100" } }` | Changing them **replaces** the load balancer |
| Certificate | `certificate = { domain_name = "example.com" }` | Publish the validation records after the apply |
| Alarms | `alarms = { email_addresses = ["platform-team@example.com"] }` | Need `access_logs.cloudwatch` |
| Dashboard | `dashboard = {}` | Needs `access_logs.cloudwatch` |
| Metric stream | `metric_stream = { firehose_arn = "...", role_arn = "..." }` | Needs a Firehose delivery stream you own |
| WAF | `waf = { create = true }`, or `waf = { web_acl_arn = "..." }` for your own web ACL | Web applications only |
| Log archive copy | `access_logs.s3 = { bucket_name = "log-archive-verified-access", bucket_owner = "111111111111" }` | The bucket is owned elsewhere |
| An existing log group | `access_logs.cloudwatch = { create_log_group = false, log_group_name = "/central/verified-access" }` | Its retention and encryption are owned elsewhere |
| Route 53 records | `dns = { zone_id = "Z0123456789ABCDEFGHIJ" }` | Certificate validation records and application CNAMEs |
| FIPS endpoints | `fips_enabled = true` | US, Canada and GovCloud regions only; changing it **replaces** the instance and everything in it |

## Moving from bastions and jump boxes

How to move a tenant that reaches a private Linux host over SSH through a bastion, and an internal web application through a hosted workstation. The example values are illustrative.

### Before and after

Before: an engineer uses an SSH key to reach a bastion in a public subnet, then SSH to the private host; for the web application, they RDP to a hosted workstation and use its browser. After: the engineer signs in with Identity Center and reaches the private host through the Connectivity Client and Verified Access (central NLB, transit gateway), and the web application directly in their own browser. The [before and after diagram](how-it-works.md#compared-with-a-bastion) and the [traffic paths](how-it-works.md#traffic-paths) show both.

### Steps

| # | Step | Who | Example |
| --- | --- | --- | --- |
| 1 | **Inventory** what the bastion and workstation are used for: hosts, ports, applications, and who uses them | Tenant + platform | SSH to `10.50.0.10:22`; web application on `10.50.0.20:80`; ten engineers |
| 2 | **Map users to identity groups**; create a group if none fits | Platform + identity owner | An `Engineers` group in the identity provider |
| 3 | **Allow the endpoint subnets** in the tenant's security groups (security groups cannot reference across a transit gateway, so use the subnet ranges) | Tenant | The endpoint subnets on ports 22 and 80 |
| 4 | **Request access** through the service desk | Tenant | — |
| 5 | **Pull request** in the deployment repository: endpoint, load balancer target, group policy, reviewed Cedar | Platform | An SSH endpoint and a web endpoint, the load balancer targets |
| 6 | **HTTPS only:** application domain CNAME to the endpoint domain; certificate validation record (once per domain) | DNS owner | `app.example.com` |
| 7 | **Distribute the Connectivity Client** and its configuration (MDM in production) | Platform / end user computing | The configuration exported from the instance, delivered by MDM |
| 8 | **Run in parallel**: users try Verified Access while the bastion remains | Tenant | — |
| 9 | **Verify**: allowed users connect, a user outside the group is denied, both appear in the logs | Platform | — |
| 10 | **Remove the bastion**, its security group rules and its keys; close the workstation entitlements | Tenant | — |

Typical effort: about one day per tenant once the platform is in place, dominated by the inventory and the client rollout. Endpoint creation takes about 17 minutes; policy changes about 10 minutes.

### What changes for users

| Gap | Impact | What to do |
| --- | --- | --- |
| **File transfer and tooling** that lived on the bastion (scripts, `scp` hops, jump configuration) | Workflows change | `scp`/`sftp` work directly to the endpoint name through the client; move tooling to the users' machines or to automation |
| **Linux users** | No Connectivity Client for Linux, so no TCP endpoints | Keep a managed access route for Linux users, or provide a supported desktop |
| **Idle sessions** | Idle TCP sessions drop after the load balancer idle timeout | SSH keep alives (`ServerAliveInterval 60`); raise `load_balancer.tcp_idle_timeout_seconds` if needed |
| **Automation and service accounts** (CI jobs that used the bastion) | Verified Access is for people | Use AWS Systems Manager, PrivateLink or pipeline roles |
| **Break glass** | If Identity Center or Verified Access is unavailable, there is no access | Keep a documented emergency route (for example Systems Manager Session Manager with approval) |

The other gaps (device posture for TCP, HTTP requests over 60 seconds, protocols other than TCP and HTTP, cost per application) are in [limitations](how-it-works.md#limitations); for cost, consolidate several ports of one service on one endpoint ([cost](cost.md)).

## Tearing down

1. In the deployment repository, run the destroy workflow. Two cases need a change first, described in [operations](operations.md#tear-down): if the pipeline role may not delete ACM certificates, and if `load_balancer.enable_deletion_protection` is on.
2. Remove the tenant side: the security group rules allowing the endpoint subnets, and the application DNS records (the CNAMEs and the certificate validation records), unless the module published them with `dns`, in which case the destroy removes them.
3. Delete the Connectivity Client configuration from users' machines (or withdraw it from MDM).
