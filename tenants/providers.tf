provider "vcfa" {
  url                  = var.vcfa_url
  org                  = var.vcfa_org
  auth_type            = "api_token"
  api_token            = var.vcfa_api_token
  allow_unverified_ssl = var.allow_unverified_ssl
}

# The org's Kubernetes API: projects, VPCs and the NSX firewall objects.
data "vcfa_kubeconfig" "org" {}

provider "kubectl" {
  alias            = "org"
  host             = data.vcfa_kubeconfig.org.host
  token            = data.vcfa_kubeconfig.org.token
  insecure         = data.vcfa_kubeconfig.org.insecure_skip_tls_verify
  load_config_file = false
}

# One provider per tenant namespace. Terraform cannot loop over providers, so
# the demo has exactly two tenants (see the validation on var.tenants). The
# namespace names are generated, so lazy_load lets these plan before the
# namespaces exist.
data "vcfa_kubeconfig" "tenant_a" {
  project_name              = module.network[local.tenant_a].project_name
  supervisor_namespace_name = module.network[local.tenant_a].namespace_name
}

provider "kubectl" {
  alias            = "tenant_a"
  host             = data.vcfa_kubeconfig.tenant_a.host
  token            = data.vcfa_kubeconfig.tenant_a.token
  insecure         = data.vcfa_kubeconfig.tenant_a.insecure_skip_tls_verify
  load_config_file = false
  lazy_load        = true
}

data "vcfa_kubeconfig" "tenant_b" {
  project_name              = module.network[local.tenant_b].project_name
  supervisor_namespace_name = module.network[local.tenant_b].namespace_name
}

provider "kubectl" {
  alias            = "tenant_b"
  host             = data.vcfa_kubeconfig.tenant_b.host
  token            = data.vcfa_kubeconfig.tenant_b.token
  insecure         = data.vcfa_kubeconfig.tenant_b.insecure_skip_tls_verify
  load_config_file = false
  lazy_load        = true
}
