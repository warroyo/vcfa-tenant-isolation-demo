# VCF Automation tenant isolation demo

## Overview

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

- **`platform/`** is built once, before any demo. It creates a `shared-services` project, VPC and namespace, a small VKS cluster (one control plane node, one worker) on a PrivateTGW subnet, and a content library holding the Ubuntu cloud image. `scripts/awx.sh` then installs AWX on that cluster and sets it up.
- **`tenants/`** is the demo. For each tenant it creates a project, VPC and namespace, a PrivateTGW subnet, an extra-small VM behind an Avi LoadBalancer on port 80, and an `AWXConnection` and `AnsibleBinding`. `isolation.tf` adds the firewall.
- **Isolation.** Each tenant VPC denies inbound and VPC-to-VPC traffic. Org-level firewall policies let only AWX, internet egress and HTTP to the VIPs back in, so traffic from one tenant to the other is dropped.

Details: [docs/explanation/architecture.md](docs/explanation/architecture.md).

## Quick start

Prerequisites:

- `terraform`, `kubectl`, `helm`, `jq` and `curl`
- An Organization Administrator API token for the org named in `tenants/tenants.auto.tfvars`
- vDefend (NSX distributed firewall) in the target environment

1. Load the token. It is never written to a file.

   ```bash
   export VCFA_API_TOKEN=...
   source scripts/env.sh                # exports TF_VAR_vcfa_api_token
   ```

2. Build the platform. This takes about 15 minutes, mostly the VKS cluster and the image upload.

   ```bash
   terraform -chdir=platform init
   terraform -chdir=platform apply
   ```

3. Install and set up AWX. This takes about 10 minutes and writes `.secrets/awx.env`.

   ```bash
   scripts/awx.sh
   ```

4. Run the demo, then reset it.

   ```bash
   scripts/demo.sh
   scripts/reset.sh
   ```

To present it, see [docs/how-to/run-the-demo.md](docs/how-to/run-the-demo.md). If a step fails, see [docs/how-to/troubleshoot.md](docs/how-to/troubleshoot.md).

## Repo structure

```
platform/     Terraform, built once: shared-services project, VPC, namespace, AWX cluster, image library
tenants/      Terraform, the demo: two tenants and the firewall between them (isolation.tf)
playbooks/    The AWX playbooks: tenant-page.yml installs the page, isolation-check.yml tests isolation
scripts/      awx.sh, demo.sh, reset.sh, check-isolation.sh, and env.sh shared by all of them
docs/         Everything beyond this page
```

Docs index: [docs/README.md](docs/README.md).
