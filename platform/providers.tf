provider "vcfa" {
  url                  = var.vcfa_url
  org                  = var.vcfa_org
  auth_type            = "api_token"
  api_token            = var.vcfa_api_token
  allow_unverified_ssl = var.allow_unverified_ssl
}

# The org's Kubernetes API in VCF Automation: projects, VPCs, NSX objects.
data "vcfa_kubeconfig" "org" {}

provider "kubectl" {
  alias            = "org"
  host             = data.vcfa_kubeconfig.org.host
  token            = data.vcfa_kubeconfig.org.token
  insecure         = data.vcfa_kubeconfig.org.insecure_skip_tls_verify
  load_config_file = false
}

# The Kubernetes API of the AWX namespace. Its name is generated, so the
# address is known only during the first apply; lazy_load lets the provider
# plan without it.
data "vcfa_kubeconfig" "awx" {
  project_name              = local.project_name
  supervisor_namespace_name = local.namespace_name
}

provider "kubectl" {
  alias            = "awx"
  host             = data.vcfa_kubeconfig.awx.host
  token            = data.vcfa_kubeconfig.awx.token
  insecure         = data.vcfa_kubeconfig.awx.insecure_skip_tls_verify
  load_config_file = false
  lazy_load        = true
}
