output "tenants" {
  description = "Each tenant's project, VPC and namespace, and its namespace's Kubernetes API address for the scripts."
  value = {
    (local.tenant_a) = {
      project   = module.network[local.tenant_a].project_name
      vpc       = module.network[local.tenant_a].vpc_name
      namespace = module.network[local.tenant_a].namespace_name
      host      = data.vcfa_kubeconfig.tenant_a.host
    }
    (local.tenant_b) = {
      project   = module.network[local.tenant_b].project_name
      vpc       = module.network[local.tenant_b].vpc_name
      namespace = module.network[local.tenant_b].namespace_name
      host      = data.vcfa_kubeconfig.tenant_b.host
    }
  }
}
