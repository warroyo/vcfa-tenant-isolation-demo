# VCF Automation tenant isolation demo

Two tenants, built by one `terraform apply` in VCF Automation. Each gets its own project, VPC, Supervisor Namespace and VM. AWX, called by the [Ansible Supervisor Service](https://github.com/warroyo/ansible-supervisor-service), installs a page on each VM. Then each tenant's VM tries to reach the other's, and the NSX firewall blocks it.

```
 shared-services VPC                 tenant-a VPC              tenant-b VPC
 ┌──────────────────┐   PrivateTGW   ┌────────────────┐        ┌────────────────┐
 │ VKS cluster: AWX ├──────ssh──────►│ tenant-a-web   │   ✗    │ tenant-b-web   │
 │                  ├──────ssh──────────────────────────────── ►│                │
 └──────────────────┘                └───────▲────────┘        └───────▲────────┘
                                             │ :80 Avi VIP              │ :80 Avi VIP
```

## How it works

- **`platform/`** is built once, before any demo. It creates a `shared-services` project, VPC and namespace, a single-node VKS cluster (control plane untainted, no workers) on a PrivateTGW subnet, and a content library holding the Ubuntu cloud image. `scripts/awx.sh` then installs AWX on that cluster and sets it up.
- **`tenants/`** is the demo. For each tenant it creates:
  - a project, a VPC, and a namespace
  - a PrivateTGW subnet
  - an extra-small VM and an Avi LoadBalancer on port 80
  - an `AWXConnection` and an `AnsibleBinding`

  `isolation.tf` adds the firewall.
- **Isolation.** Each tenant VPC gets the built-in *VPC External Connectivity* security profile, which allows outbound traffic and denies inbound and VPC-to-VPC traffic. Three org-level Infrastructure firewall policies sit in front of it and let three things back in:
  - AWX, matched as the shared-services VPC object rather than an IP
  - internet egress
  - HTTP to the load balancer VIPs

  Traffic from one tenant to the other matches none of them. The policies need vDefend (NSX distributed firewall).

## Before the demo

Tools: `terraform`, `kubectl`, `helm`, `jq`, `curl`.

Access: an Organization Administrator API token for the org named in `tenants/tenants.auto.tfvars`.

```bash
export VCFA_API_TOKEN=...            # never in a file
source scripts/env.sh                # exports TF_VAR_vcfa_api_token

terraform -chdir=platform init
terraform -chdir=platform apply      # about 15 minutes, mostly the VKS cluster and the image upload
scripts/awx.sh                       # about 10 minutes; writes .secrets/awx.env
```

Run `scripts/demo.sh` and then `scripts/reset.sh` once beforehand, so you know the demo works on the day.

## Run the demo

```bash
scripts/demo.sh
```

| Step | Show | Why |
|---|---|---|
| 1 | `terraform apply` creating `tenant-a` and `tenant-b`. Then, in VCF Automation, the two new projects and their namespaces | The person asking for the environments never touches Kubernetes. They get self-service infrastructure from a single apply. |
| 2 | The VMs getting IPs, then `ansible: Succeeded`. In AWX, the two jobs and the hosts named `tenant-a-…` and `tenant-b-…` | Configuration runs automatically, with each tenant's own AWX connection. The VMs never had nginx in their image. |
| 3 | Both VIPs in a browser: a blue page and an orange page | Each tenant's workload is reachable on its own load balancer. |
| 4 | `BLOCKED tenant-a -> 172.31.x.x`, in both directions. The AWX job output shows the failed connection attempts | The tenants share a transit gateway, but the VPC firewall keeps them apart. AWX is allowed in as an object, not an IP. |

## After the demo

```bash
scripts/reset.sh
```

This removes both tenants and leaves `platform/` and AWX in place for the next run. To remove everything, run `terraform -chdir=platform destroy`.

## Troubleshooting

- **`ansible: Failed`.** Open the job in AWX. If it fails at SSH, the VM was probably still running cloud-init. Bump the `ansible.field.vmware.com/reconcile-requested-at` annotation on the `AnsibleBinding`, and it runs again.
- **A VIP times out but the job succeeded.** Check that `tenant-vip-http` and `tenant-mgmt` are `Realized`: `kubectl get firewallpolicies.vpc.nsx.vmware.com` with the org kubeconfig. Also check that `vip_range` matches the connectivity profile's external IP block.
- **`awx.sh` stops at the project sync.** AWX could not clone `REPO_URL`. The cluster nodes need internet egress through the shared-services VPC.
