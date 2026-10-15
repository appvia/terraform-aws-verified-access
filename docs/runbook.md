# Runbook

Operating Verified Access deployed with this module through a deployment repository (from `appvia/terraform-aws-pipeline-template`).

## Give someone access to an application

1. Find the Identity Center group ID (or OIDC group name) for the audience.
2. In the deployment repository, change `groups` in `values/production.tfvars`.
3. Run `terraform test -var-file=values/production.tfvars`. It fails because the rendered policy changed: update the matching file in `policies/` with the new Cedar (the failure shows which), then run it again.
4. Open a pull request; check the plan; get a code owner review; merge.
5. **Allow about 10 minutes** after the apply before the change takes effect.

Revoking access is the same change in reverse, with the same delay.

## Add an application

1. The tenant allows the endpoint subnets on the application's port in its security group.
2. Add an endpoint under the right group (`type = "load-balancer"`; TCP with `port_ranges`, or HTTP with `port` and `application_domain`) and a matching entry in `load_balancer_targets` with the application's private IPs. Each application needs its own port on the central load balancer.
3. HTTPS only: make sure the certificate covers the application domain, then add a CNAME from the application domain to the endpoint domain (output `endpoint_domains`).
4. Merge. **A new endpoint takes about 17 minutes** to become active; the pipeline waits for it.

## Connect over TCP (SSH, RDP, databases)

1. Install the [AWS Verified Access Connectivity Client](https://docs.aws.amazon.com/verified-access/latest/ug/connectivity-client.html) (macOS or Windows; signed installer only). Disconnect other VPNs; keep IPv6 enabled.
2. Get the configuration file: `aws ec2 export-verified-access-instance-client-configuration --verified-access-instance-id <instance_id>` saved as `ClientConfig-<anything>.json`. It needs `ec2:ExportVerifiedAccessInstanceClientConfiguration`, which read-only and engineer roles often lack; a manual workflow using the pipeline role is a simple way to provide it. In production, distribute it through MDM.
3. Install it, owned by root:
   ```bash
   sudo mkdir -p "/Library/Application Support/Connectivity Client"
   sudo cp ClientConfig-*.json "/Library/Application Support/Connectivity Client/"
   sudo chown root "/Library/Application Support/Connectivity Client/"ClientConfig-*.json
   ```
4. Open the client and sign in.
5. Connect to the endpoint domain (output `endpoint_domains`), for example `ssh ec2-user@<endpoint>.<instance>.prod.verified-access.<region>.amazonaws.com`.

## Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| `Could not resolve hostname` for a TCP endpoint | The client is not connected; TCP endpoint names resolve to **IPv6 only** | The client shows Connected; `ifconfig` shows a tunnel interface with an IPv6 address |
| TCP connection **times out** | **Denied** by policy (a denial looks like a timeout to the client), or the target is down | `denied-requests` saved query (logs arrive 3 to 5 minutes later); NLB target health |
| Browser shows **403** | Denied by policy | `denied-requests` saved query: the user's groups are in the event |
| Everyone is denied with Identity Center | The directory reports `email.verified = false` and `require_verified_email = true` | `context.idc.user.email.verified` in a log event; set `require_verified_email = false` |
| A policy change "did not work" | Propagation | Wait 10 minutes; confirm the policy with `aws ec2 get-verified-access-group-policy` |
| SSH session drops when idle | Load balancer idle timeout (350 seconds) | `ssh -o ServerAliveInterval=60`; or raise the listener idle timeout |
| HTTP 504 | The application took longer than 60 seconds | `Http504` metric; the application |
| Pipeline: `AssumeRoleWithWebIdentity` denied | The role trusts a different OIDC subject; new repositories use the immutable form `org@<id>/repo@<id>` | The repository's `actions/oidc/customization/sub`; the role's `repository` value |
| Pipeline: `jq: parse error` before Terraform | Transient GitHub token error | Re-run the failed jobs |
| Pipeline: `Saved plan is stale` | Re-ran only the apply after an earlier failure | Start a fresh run (`workflow_dispatch` on `main`) |

## Alarms

See [observability](observability.md). In quiet environments the "logging stopped" and "no successful access" alarms are expected to fire.

## Tear down

1. Deployment repository: run the destroy workflow. If the pipeline role is not allowed to delete ACM certificates, first remove the certificate from state with a `removed` block (`lifecycle { destroy = false }`); an unused public certificate is free and expires.
2. Remove the tenant side: security group rules for the endpoint subnets and the application DNS records.
