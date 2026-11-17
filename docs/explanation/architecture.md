# Architecture

```mermaid
flowchart LR
  tf["terraform apply<br/>(tenants/)"]
  user["Browser"]
  internet(("Internet"))

  subgraph org["VCF Automation org"]
    subgraph shared["shared-services VPC"]
      subgraph awxns["Supervisor Namespace"]
        awx["VKS cluster: AWX"]
      end
    end

    tgw{{"Transit gateway<br/>(PrivateTGW subnets, no SNAT)"}}

    subgraph a["tenant-a VPC"]
      subgraph ans["Supervisor Namespace"]
        abind["AWXConnection +<br/>AnsibleBinding"]
        avm["tenant-a-web VM"]
        avip["Avi VIP :80"]
      end
    end

    subgraph b["tenant-b VPC"]
      subgraph bns["Supervisor Namespace"]
        bbind["AWXConnection +<br/>AnsibleBinding"]
        bvm["tenant-b-web VM"]
        bvip["Avi VIP :80"]
      end
    end

    fw["Org firewall policies<br/>tenant-mgmt, tenant-egress, tenant-vip-http"]
  end

  tf -->|projects, VPCs, namespaces,<br/>VMs, firewall| org
  abind -->|launch job| awx
  bbind -->|launch job| awx
  awx -->|ssh| tgw
  tgw -->|ssh: allowed by tenant-mgmt| avm
  tgw -->|ssh: allowed by tenant-mgmt| bvm
  user -->|HTTP: allowed by tenant-vip-http| avip --> avm
  user -->|HTTP: allowed by tenant-vip-http| bvip --> bvm
  avm -->|allowed by tenant-egress| internet
  avm --x|blocked| bvm
  fw -.-|applied to| a
  fw -.-|applied to| b
```

The Ansible Supervisor Service watches each tenant's `AnsibleBinding` and launches the job in AWX through that tenant's `AWXConnection`. AWX then reaches the VM over SSH. Each tenant VPC's security profile denies everything else inbound, including traffic from the other tenant.

## Isolation

Each tenant VPC gets the built-in *VPC External Connectivity* security profile, which allows outbound traffic and denies inbound and VPC-to-VPC traffic. Three org-level Infrastructure firewall policies in `tenants/isolation.tf` sit in front of it and let three things back in:

- AWX, matched as the shared-services VPC object rather than an IP
- internet egress
- HTTP to the load balancer VIPs

Traffic from one tenant to the other matches none of them. The policies need vDefend (NSX distributed firewall). All of it is org scope, so an Organization Administrator can create it.

AWX reaches the tenant VMs because its cluster nodes sit on a PrivateTGW subnet. Traffic from them crosses the transit gateway without SNAT, so the tenant firewall can allow "the shared-services VPC" as an object instead of an IP.

## Gotchas

- **Image names must be unique in the org.** VM Operator refuses an image name that matches more than one image visible to a namespace, and any library in the org can add one. The image is named `tenant-demo-ubuntu-24.04` for that reason.
- **The guest LoadBalancer status can stall after a node rollout.** The likely cause: when the cloud provider starts while no worker is ready, it ensures the load balancer with no backends, and the service's address stays empty after the worker joins. A restart of the cloud provider writes it.
- **NSX purges deleted VPC names after up to 5 minutes.** Recreating a tenant before then fails with `is marked for deletion`.
- **NSX refuses to delete a subnet while a VM's subnet port remains.** The tenant VM resource waits for its delete to finish before Terraform deletes the subnet.
- **Helm 4 hangs on HTTP/2 to the cluster's load-balanced API address.** `awx.sh` sets `DISABLE_HTTP2=true`.
