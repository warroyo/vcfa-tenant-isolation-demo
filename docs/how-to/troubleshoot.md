# Troubleshoot the demo

- **`ansible: Failed`.** Open the job in AWX. If it fails at SSH, the VM was probably still running cloud-init. Bump the `ansible.field.vmware.com/reconcile-requested-at` annotation on the `AnsibleBinding`, and it runs again.
- **A VIP times out but the job succeeded.** Check that `tenant-vip-http` and `tenant-mgmt` are `Realized`: `kubectl get firewallpolicies.vpc.nsx.vmware.com` with the org kubeconfig. Also check that `vip_range` matches the connectivity profile's external IP block.
- **`awx.sh` waits forever for AWX, but the pods are Running.** The `awx-service` LoadBalancer shows `<pending>` in the AWX cluster, even though the Supervisor has given it an address. This happens after a node rollout. Restart the cluster's cloud provider: `kubectl -n vmware-system-cloud-provider rollout restart deploy/guest-cluster-cloud-provider`.
- **The demo fails with `is marked for deletion`.** It ran within 5 minutes of a reset. Wait, then run it again.
- **`awx.sh` stops at the project sync.** AWX could not clone `REPO_URL`. The cluster nodes need internet egress through the shared-services VPC.
