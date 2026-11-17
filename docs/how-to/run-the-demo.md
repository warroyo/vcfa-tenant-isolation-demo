# Run the demo

Run `scripts/demo.sh` and then `scripts/reset.sh` once beforehand, so you know the demo works on the day.

1. Start the demo:

   ```bash
   scripts/demo.sh
   ```

2. Present each step:

   | Step | Show | Why |
   |---|---|---|
   | 1 | `terraform apply` creating `tenant-a` and `tenant-b`. Then, in VCF Automation, the two new projects and their namespaces | The person asking for the environments never touches Kubernetes. They get self-service infrastructure from a single apply. |
   | 2 | The VMs getting IPs, then `ansible: Succeeded`. In AWX, the two jobs and the hosts named `tenant-a-…` and `tenant-b-…` | Configuration runs automatically, with each tenant's own AWX connection. The VMs never had nginx in their image. |
   | 3 | Both VIPs in a browser: a blue page and an orange page | Each tenant's workload is reachable on its own load balancer. |
   | 4 | `BLOCKED tenant-a -> 172.31.x.x`, in both directions. The AWX job output shows the failed connection attempts | The tenants share a transit gateway, but the VPC firewall keeps them apart. AWX is allowed in as an object, not an IP. |

3. After the demo, remove both tenants:

   ```bash
   scripts/reset.sh
   ```

   This leaves `platform/` and AWX in place for the next run. NSX keeps deleted VPC names for up to 5 minutes, so wait that long before running the demo again.

4. To remove everything, run `terraform -chdir=platform destroy`.
