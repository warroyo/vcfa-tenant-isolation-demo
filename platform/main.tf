# Shared services: one project, one VPC and one namespace holding the VKS
# cluster AWX runs on. Built once, before the demo.
#
# The cluster's nodes sit on a PrivateTGW subnet. Traffic from them to the
# tenant VMs then crosses the transit gateway without SNAT, so the tenant
# firewall can allow "the shared services VPC" as an object instead of an IP.

locals {
  project_name = var.name
  vpc_name     = var.name
}

resource "kubectl_manifest" "project" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "project.cci.vmware.com/v1alpha2"
    kind       = "Project"
    metadata   = { name = local.project_name }
    spec       = { description = "Shared services for the tenant isolation demo: AWX." }
  })

  # Projects reject the last-applied annotation a client-side apply adds.
  server_side_apply = true
}

resource "kubectl_manifest" "vpc" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "VPC"
    metadata   = { name = local.vpc_name }
    spec = {
      description             = "Shared services VPC for the tenant isolation demo."
      regionName              = var.region_name
      privateIPs              = [var.vpc_cidr]
      loadBalancerVPCEndpoint = { enabled = true }
    }
  })
}

resource "kubectl_manifest" "vpc_attachment" {
  provider = kubectl.org

  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "VPCAttachment"
    metadata   = { name = "${local.vpc_name}:default" }
    spec = {
      regionName                 = var.region_name
      vpcName                    = local.vpc_name
      vpcConnectivityProfileName = var.vpc_connectivity_profile
    }
  })

  depends_on = [kubectl_manifest.vpc]
}

# Sized for two small node VMs and a 2Gi Postgres volume. VM classes are
# best-effort, so nothing is reserved.
resource "vcfa_supervisor_namespace" "awx" {
  name_prefix  = "awx"
  description  = "AWX for the tenant isolation demo."
  project_name = local.project_name
  region_name  = var.region_name
  vpc_name     = local.vpc_name
  class_name   = "small"
  seg_name     = var.seg_name

  storage_classes_class_config_overrides {
    name  = var.storage_class
    limit = "80Gi"
  }

  zones_class_config_overrides {
    name               = var.zone_name
    cpu_limit          = "10000M"
    cpu_reservation    = "0M"
    memory_limit       = "16Gi"
    memory_reservation = "0Mi"
  }

  depends_on = [kubectl_manifest.project, kubectl_manifest.vpc_attachment]
}

# Read the generated name through a local, so the kubeconfig lookup in
# providers.tf does not wait for every pending change on the namespace.
locals {
  namespace_name = vcfa_supervisor_namespace.awx.name
}

# VKS node networks must be a SubnetSet, not a Subnet.
resource "kubectl_manifest" "awx_subnet" {
  provider = kubectl.awx

  yaml_body = yamlencode({
    apiVersion = "crd.nsx.vmware.com/v1alpha1"
    kind       = "SubnetSet"
    metadata   = { name = "awx-tgw", namespace = local.namespace_name }
    spec       = { accessMode = "PrivateTGW", ipv4SubnetSize = 16 }
  })
}

resource "kubectl_manifest" "awx_cluster" {
  provider = kubectl.awx

  yaml_body = yamlencode({
    apiVersion = "cluster.x-k8s.io/v1beta2"
    kind       = "Cluster"
    metadata   = { name = var.awx_cluster.name, namespace = local.namespace_name }
    spec = {
      clusterNetwork = {
        pods          = { cidrBlocks = ["192.168.0.0/16"] }
        services      = { cidrBlocks = ["10.96.0.0/12"] }
        serviceDomain = "cluster.local"
      }
      topology = {
        classRef     = { name = var.awx_cluster.class, namespace = "vmware-system-vks-public" }
        version      = var.awx_cluster.version
        controlPlane = { replicas = 1 }
        workers = {
          machineDeployments = [{
            class    = "node-pool"
            name     = "${var.awx_cluster.name}-np"
            replicas = 1
            variables = {
              overrides = [{ name = "vmClass", value = var.awx_cluster.worker_class }]
            }
          }]
        }
        variables = [
          { name = "vmClass", value = var.awx_cluster.control_plane_class },
          { name = "storageClass", value = var.storage_class },
          {
            name = "networks"
            value = {
              interfaces = {
                primary = {
                  network = {
                    apiVersion = "crd.nsx.vmware.com/v1alpha1"
                    kind       = "SubnetSet"
                    name       = "awx-tgw"
                  }
                }
              }
            }
          },
        ]
      }
    }
  })

  depends_on = [kubectl_manifest.awx_subnet]
}
