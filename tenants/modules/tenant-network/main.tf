# One tenant's project, VPC and Supervisor Namespace, and the security
# profile that isolates its VPC.

terraform {
  required_providers {
    vcfa    = { source = "vmware/vcfa" }
    kubectl = { source = "alekc/kubectl" }
  }
}

variable "name" {
  type        = string
  description = "Tenant key. Names the project and the VPC."
}

variable "cidr" {
  type        = string
  description = "Private CIDR of the tenant VPC."
}

variable "region_name" {
  type = string
}

variable "zone_name" {
  type = string
}

variable "storage_class" {
  type = string
}

variable "seg_name" {
  type = string
}

variable "vpc_connectivity_profile" {
  type = string
}

variable "security_profile" {
  type        = string
  description = "Built-in VPC External Connectivity: outbound allowed, inbound and VPC-to-VPC denied."
  default     = "system-security-profile-4--ans-cluster"
}

resource "kubectl_manifest" "project" {
  yaml_body = yamlencode({
    apiVersion = "project.cci.vmware.com/v1alpha2"
    kind       = "Project"
    metadata   = { name = var.name }
    spec       = { description = "Tenant isolation demo: ${var.name}." }
  })

  # Projects reject the last-applied annotation a client-side apply adds.
  server_side_apply = true
}

resource "kubectl_manifest" "vpc" {
  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "VPC"
    metadata   = { name = var.name }
    spec = {
      description             = "Tenant isolation demo: ${var.name}."
      regionName              = var.region_name
      privateIPs              = [var.cidr]
      loadBalancerVPCEndpoint = { enabled = true }
    }
  })
}

resource "kubectl_manifest" "vpc_attachment" {
  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "VPCAttachment"
    metadata   = { name = "${var.name}:default" }
    spec = {
      regionName                 = var.region_name
      vpcName                    = var.name
      vpcConnectivityProfileName = var.vpc_connectivity_profile
    }
  })

  depends_on = [kubectl_manifest.vpc]
}

# Room for one extra-small VM and its 10Gi disk.
resource "vcfa_supervisor_namespace" "tenant" {
  name_prefix  = var.name
  description  = "Tenant isolation demo: ${var.name}."
  project_name = var.name
  region_name  = var.region_name
  vpc_name     = var.name
  class_name   = "small"
  seg_name     = var.seg_name

  storage_classes_class_config_overrides {
    name  = var.storage_class
    limit = "20Gi"
  }

  zones_class_config_overrides {
    name               = var.zone_name
    cpu_limit          = "4000M"
    cpu_reservation    = "0M"
    memory_limit       = "4Gi"
    memory_reservation = "0Mi"
  }

  depends_on = [kubectl_manifest.project, kubectl_manifest.vpc_attachment]
}

# VCF Automation creates this attachment with the default profile when the
# VPC is created. Server-side apply with force takes it over and sets the
# profile. Destroy leaves it: it goes with the VPC.
resource "kubectl_manifest" "security_profile" {
  yaml_body = yamlencode({
    apiVersion = "vpc.nsx.vmware.com/v1alpha1"
    kind       = "SecurityProfileAttachment"
    metadata   = { name = var.name }
    spec = {
      regionName          = var.region_name
      vpcName             = var.name
      securityProfileName = var.security_profile
    }
  })

  server_side_apply = true
  force_conflicts   = true
  apply_only        = true

  # Waiting for the namespace gives VCF Automation time to create its own
  # attachment first.
  depends_on = [vcfa_supervisor_namespace.tenant]
}

output "project_name" {
  value = var.name
}

output "vpc_name" {
  value = var.name
}

output "namespace_name" {
  value = vcfa_supervisor_namespace.tenant.name
}
