# Two tenants, each with its own project, VPC, namespace and VM. AWX in the
# shared services VPC configures the VMs; the firewall in isolation.tf keeps
# the tenants apart.

data "terraform_remote_state" "platform" {
  backend = "local"
  config  = { path = "${path.module}/../platform/terraform.tfstate" }
}

locals {
  platform = data.terraform_remote_state.platform.outputs
  tenant_a = sort(keys(var.tenants))[0]
  tenant_b = sort(keys(var.tenants))[1]
}

module "network" {
  source   = "./modules/tenant-network"
  for_each = var.tenants

  providers = {
    vcfa    = vcfa
    kubectl = kubectl.org
  }

  name                     = each.key
  cidr                     = each.value.cidr
  region_name              = var.region_name
  zone_name                = var.zone_name
  storage_class            = var.storage_class
  seg_name                 = var.seg_name
  vpc_connectivity_profile = var.vpc_connectivity_profile
}

locals {
  workload = {
    image_name     = local.platform.image_name
    vm_class       = var.vm_class
    storage_class  = var.storage_class
    ssh_public_key = trimspace(file(var.ssh_public_key_file))
    awx_url        = var.awx_url
    awx_token      = var.awx_token
  }
}

module "workload_a" {
  source    = "./modules/tenant-workload"
  providers = { kubectl = kubectl.tenant_a }

  name         = local.tenant_a
  display_name = var.tenants[local.tenant_a].display_name
  color        = var.tenants[local.tenant_a].color
  namespace    = module.network[local.tenant_a].namespace_name
  vpc_name     = module.network[local.tenant_a].vpc_name

  image_name     = local.workload.image_name
  vm_class       = local.workload.vm_class
  storage_class  = local.workload.storage_class
  ssh_public_key = local.workload.ssh_public_key
  awx_url        = local.workload.awx_url
  awx_token      = local.workload.awx_token
}

module "workload_b" {
  source    = "./modules/tenant-workload"
  providers = { kubectl = kubectl.tenant_b }

  name         = local.tenant_b
  display_name = var.tenants[local.tenant_b].display_name
  color        = var.tenants[local.tenant_b].color
  namespace    = module.network[local.tenant_b].namespace_name
  vpc_name     = module.network[local.tenant_b].vpc_name

  image_name     = local.workload.image_name
  vm_class       = local.workload.vm_class
  storage_class  = local.workload.storage_class
  ssh_public_key = local.workload.ssh_public_key
  awx_url        = local.workload.awx_url
  awx_token      = local.workload.awx_token
}
