# One tenant's VM, its load balancer, and the AnsibleBinding that has AWX
# install the tenant page on it.

terraform {
  required_providers {
    kubectl = { source = "alekc/kubectl" }
  }
}

variable "name" {
  type = string
}

variable "display_name" {
  type = string
}

variable "color" {
  type = string
}

variable "namespace" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "image_name" {
  type = string
}

variable "vm_class" {
  type = string
}

variable "storage_class" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "awx_url" {
  type = string
}

variable "awx_token" {
  type      = string
  sensitive = true
}

locals {
  vm_name = "${var.name}-web"
  labels  = { app = "tenant-page" }
}

# PrivateTGW: AWX, in the shared services VPC, reaches the VM across the
# transit gateway. The tenant firewall decides who else can.
resource "kubectl_manifest" "subnet" {
  yaml_body = yamlencode({
    apiVersion = "crd.nsx.vmware.com/v1alpha1"
    kind       = "Subnet"
    metadata   = { name = "tgw", namespace = var.namespace }
    spec       = { accessMode = "PrivateTGW", ipv4SubnetSize = 16 }
  })
}

# Creates the user AWX logs in as. AWX installs everything else.
resource "kubectl_manifest" "cloud_init" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata   = { name = "${local.vm_name}-cloud-init", namespace = var.namespace }
    type       = "Opaque"
    data = {
      user-data = base64encode(<<-EOT
        #cloud-config
        hostname: ${local.vm_name}
        users:
          - name: ansible
            sudo: ALL=(ALL) NOPASSWD:ALL
            shell: /bin/bash
            ssh_authorized_keys:
              - ${var.ssh_public_key}
        ssh_pwauth: false
      EOT
      )
    }
  })
}

resource "kubectl_manifest" "vm" {
  yaml_body = yamlencode({
    apiVersion = "vmoperator.vmware.com/v1alpha3"
    kind       = "VirtualMachine"
    metadata   = { name = local.vm_name, namespace = var.namespace, labels = local.labels }
    spec = {
      className    = var.vm_class
      imageName    = var.image_name
      storageClass = var.storage_class
      powerState   = "PoweredOn"
      bootstrap = {
        cloudInit = { rawCloudConfig = { name = "${local.vm_name}-cloud-init", key = "user-data" } }
      }
      network = {
        interfaces = [{
          name    = "eth0"
          network = { apiVersion = "crd.nsx.vmware.com/v1alpha1", kind = "Subnet", name = "tgw" }
        }]
      }
    }
  })

  depends_on = [kubectl_manifest.subnet, kubectl_manifest.cloud_init]
}

resource "kubectl_manifest" "lb" {
  yaml_body = yamlencode({
    apiVersion = "vmoperator.vmware.com/v1alpha3"
    kind       = "VirtualMachineService"
    metadata   = { name = local.vm_name, namespace = var.namespace }
    spec = {
      type     = "LoadBalancer"
      selector = local.labels
      ports    = [{ name = "http", port = 80, targetPort = 80, protocol = "TCP" }]
    }
  })
}

resource "kubectl_manifest" "awx_token" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata   = { name = "awx-token", namespace = var.namespace }
    type       = "Opaque"
    data       = { token = base64encode(var.awx_token) }
  })

  sensitive_fields = ["data"]
}

resource "kubectl_manifest" "awx_connection" {
  yaml_body = yamlencode({
    apiVersion = "field.vmware.com/v1"
    kind       = "AWXConnection"
    metadata   = { name = "awx", namespace = var.namespace }
    spec = {
      url            = var.awx_url
      secretRef      = "awx-token"
      hostNamePrefix = "${var.name}-"
    }
  })

  depends_on = [kubectl_manifest.awx_token]
}

# On destroy this goes first, while the VM and the connection still exist:
# its finalizer takes the VM's host back out of the AWX inventory.
resource "kubectl_manifest" "binding" {
  yaml_body = yamlencode({
    apiVersion = "field.vmware.com/v1"
    kind       = "AnsibleBinding"
    metadata   = { name = "tenant-page", namespace = var.namespace }
    spec = {
      vmSelector       = local.labels
      awxConnectionRef = "awx"
      template         = { name = "Install tenant page", type = "JobTemplate" }
      extraVars = {
        tenant_name    = var.display_name
        tenant_color   = var.color
        tenant_project = var.name
        tenant_vpc     = var.vpc_name
      }
    }
  })

  depends_on = [kubectl_manifest.vm, kubectl_manifest.awx_connection]
}

output "vm_name" {
  value = local.vm_name
}
