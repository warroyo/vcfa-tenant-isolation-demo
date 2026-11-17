# Architecture

## Isolation

Each tenant VPC gets the built-in *VPC External Connectivity* security profile, which allows outbound traffic and denies inbound and VPC-to-VPC traffic. Three org-level Infrastructure firewall policies in `tenants/isolation.tf` sit in front of it and let three things back in:

- AWX, matched as the shared-services VPC object rather than an IP
- internet egress
- HTTP to the load balancer VIPs

Traffic from one tenant to the other matches none of them. The policies need vDefend (NSX distributed firewall). All of it is org scope, so an Organization Administrator can create it.

AWX reaches the tenant VMs because its cluster nodes sit on a PrivateTGW subnet. Traffic from them crosses the transit gateway without SNAT, so the tenant firewall can allow "the shared-services VPC" as an object instead of an IP.

## The AWX cluster

The cluster has one control plane node and one worker, the smallest supported shape.

- **Why not one node.** Several VKS system pods (vks-agent, gatekeeper, policy-sync and others) do not tolerate the control-plane taint, so a single node only works with the taint removed. That is unsupported. The `builtin-generic-v3.8.0` ClusterClass documents a `node.taints` variable, but setting it to `[]` has no effect, and removing the taint by hand marks the CAPI Machine `Ready=False`.
- **Sizes.** The control plane uses `best-effort-small` (2 vCPU, 4Gi). The worker uses `best-effort-awx-worker` (3 vCPU, 6Gi), a custom class made by hand in vCenter for this lab and set in `platform/lab.auto.tfvars`. With system pods and AWX, the worker needs about 2.2 vCPU and 3.5Gi of requests.
- **Disk.** The worker has a 20Gi containerd disk. Without it, pulling the AWX execution environment image fills the 16Gi root disk, and the kubelet evicts AWX.
- **Storage quota.** Each node's root disk counts as a 20Gi volume against the namespace's storage limit. With the containerd disk and the 2Gi Postgres volume that is 82Gi, plus 40Gi while a worker rolls out, so the limit is 130Gi. VM classes are best-effort, so nothing is reserved.

## Gotchas

- **Image names must be unique in the org.** VM Operator refuses an image name that matches more than one image visible to a namespace, and any library in the org can add one. The image is named `tenant-demo-ubuntu-24.04` for that reason.
- **The guest LoadBalancer status can stall after a node rollout.** The likely cause: when the cloud provider starts while no worker is ready, it ensures the load balancer with no backends, and the service's address stays empty after the worker joins. A restart of the cloud provider writes it.
- **NSX purges deleted VPC names after up to 5 minutes.** Recreating a tenant before then fails with `is marked for deletion`.
- **NSX refuses to delete a subnet while a VM's subnet port remains.** The tenant VM resource waits for its delete to finish before Terraform deletes the subnet.
- **Helm 4 hangs on HTTP/2 to the cluster's load-balanced API address.** `awx.sh` sets `DISABLE_HTTP2=true`.
