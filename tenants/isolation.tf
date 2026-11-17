# Network isolation between the tenants. All of it is org scope, so an
# Organization Administrator can create it.
#
# Each tenant VPC gets the built-in "VPC External Connectivity" profile (see
# modules/tenant-network): outbound allowed, inbound and VPC-to-VPC denied.
# On its own that profile also breaks three things the demo needs, so three
# Infrastructure policies, evaluated before it, put them back:
#
#   tenant-mgmt          AWX (the shared services VPC) and the Avi Service
#                        Engines reach the tenant VMs.
#   tenant-egress        The VMs reach the internet. The profile's deny also
#                        sits on the VPC's own service gateway ports, where the
#                        packet arrives already SNATed, so "allow out" from the
#                        VM is not enough: this allows any source to anything
#                        outside the private ranges.
#   tenant-vip-http      Anyone reaches the load balancer VIPs on HTTP. The Avi
#                        Service Engine NICs sit inside the tenant VPC.
#
# Tenant to tenant matches none of these, so the profile drops it.

locals {
  avi_service_engine_range = "100.64.0.0/10"
  private_ranges           = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"]
}

resource "kubectl_manifest" "group_tenant_vpcs" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "NetworkSecurityGroup"
    metadata   = { name = "tenant-vpcs" }
    spec       = { regionName = var.region_name, vpcNames = [for t in module.network : t.vpc_name] }
  })
}

# A group with VPC members cannot also hold IPs, so the shared services VPC
# and the Avi range are two groups.
resource "kubectl_manifest" "group_shared_services" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "NetworkSecurityGroup"
    metadata   = { name = "tenant-mgmt-shared-services" }
    spec       = { regionName = var.region_name, vpcNames = [local.platform.vpc_name] }
  })
}

resource "kubectl_manifest" "group_avi_service_engines" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "NetworkSecurityGroup"
    metadata   = { name = "tenant-mgmt-avi" }
    spec       = { regionName = var.region_name, ipAddresses = [local.avi_service_engine_range] }
  })
}

resource "kubectl_manifest" "group_private_ranges" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "NetworkSecurityGroup"
    metadata   = { name = "tenant-private-ranges" }
    spec       = { regionName = var.region_name, ipAddresses = local.private_ranges }
  })
}

resource "kubectl_manifest" "group_lb_vips" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "NetworkSecurityGroup"
    metadata   = { name = "tenant-lb-vips" }
    spec       = { regionName = var.region_name, ipAddresses = [var.vip_range] }
  })
}

resource "kubectl_manifest" "policy_mgmt" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "FirewallPolicy"
    metadata   = { name = "tenant-mgmt" }
    spec = {
      regionName = var.region_name
      category   = "Infrastructure"
      priority   = 10
      stateful   = true
      appliedTo  = { groupNames = ["tenant-vpcs"] }
      rules = [{
        name      = "allow-awx-and-avi"
        action    = "Allow"
        direction = "In"
        from      = [{ groupName = "tenant-mgmt-shared-services" }, { groupName = "tenant-mgmt-avi" }]
        to        = [{ groupName = "Any" }]
        services  = [{ networkServiceName = "Any" }]
      }]
    }
  })

  depends_on = [kubectl_manifest.group_tenant_vpcs, kubectl_manifest.group_shared_services, kubectl_manifest.group_avi_service_engines]
}

resource "kubectl_manifest" "policy_egress" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "FirewallPolicy"
    metadata   = { name = "tenant-egress" }
    spec = {
      regionName = var.region_name
      category   = "Infrastructure"
      priority   = 20
      stateful   = true
      appliedTo  = { groupNames = ["tenant-vpcs"] }
      rules = [{
        name                 = "allow-internet"
        action               = "Allow"
        direction            = "InOut"
        from                 = [{ groupName = "Any" }]
        to                   = [{ groupName = "tenant-private-ranges" }]
        destinationsExcluded = true
        services             = [{ networkServiceName = "Any" }]
      }]
    }
  })

  depends_on = [kubectl_manifest.group_tenant_vpcs, kubectl_manifest.group_private_ranges]
}

resource "kubectl_manifest" "policy_vip_http" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "FirewallPolicy"
    metadata   = { name = "tenant-vip-http" }
    spec = {
      regionName = var.region_name
      category   = "Infrastructure"
      priority   = 30
      stateful   = true
      appliedTo  = { groupNames = ["tenant-vpcs"] }
      rules = [{
        name      = "allow-http-to-vips"
        action    = "Allow"
        direction = "InOut"
        from      = [{ groupName = "Any" }]
        to        = [{ groupName = "tenant-lb-vips" }]
        services  = [{ networkServiceName = ":HTTP" }]
      }]
    }
  })

  depends_on = [kubectl_manifest.group_tenant_vpcs, kubectl_manifest.group_lb_vips]
}
