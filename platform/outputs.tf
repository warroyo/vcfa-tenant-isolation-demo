# tenants/ reads these from this root's state.

output "vpc_name" {
  description = "The shared services VPC. The tenant firewall allows it in."
  value       = local.vpc_name
}

output "project_name" {
  value = local.project_name
}

output "namespace_name" {
  value = local.namespace_name
}

output "namespace_host" {
  description = "Kubernetes API address of the AWX namespace, for scripts/awx.sh."
  value       = data.vcfa_kubeconfig.awx.host
}

output "awx_cluster_name" {
  value = var.awx_cluster.name
}

output "image_name" {
  description = "imageName for the tenant VMs."
  value       = vcfa_content_library_item.ubuntu.name
}
