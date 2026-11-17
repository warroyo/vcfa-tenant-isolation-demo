# --- VCF Automation ---

variable "vcfa_url" {
  type = string
}

variable "vcfa_org" {
  type = string
}

variable "vcfa_api_token" {
  type        = string
  description = "An Organization Administrator's API token. Set it with TF_VAR_vcfa_api_token in .env."
  sensitive   = true
}

variable "allow_unverified_ssl" {
  type    = bool
  default = true
}

# --- Region ---

variable "region_name" {
  type = string
}

variable "zone_name" {
  type = string
}

variable "storage_class" {
  type        = string
  description = "Storage class for the namespaces and VMs, by its Kubernetes name."
}

variable "seg_name" {
  type        = string
  description = "Avi Service Engine Group. Required in a region that uses Avi."
}

variable "vpc_connectivity_profile" {
  type = string
}

variable "vip_range" {
  type        = string
  description = "Range the load balancer VIPs come from (the connectivity profile's external IP block). The tenant firewall allows HTTP to it."
}

# --- Tenants ---

variable "tenants" {
  type = map(object({
    display_name = string
    color        = string
    cidr         = string
  }))
  description = "The two tenants, by key. The key names the project and VPC."

  validation {
    condition     = length(var.tenants) == 2
    error_message = "The demo has exactly two tenants: Terraform needs one provider per tenant namespace and cannot loop over providers."
  }
}

variable "vm_class" {
  type    = string
  default = "best-effort-xsmall"
}

# --- AWX, from scripts/awx.sh ---

variable "awx_url" {
  type        = string
  description = "AWX address. demo.sh reads it from .secrets/awx.env."
}

variable "awx_token" {
  type        = string
  description = "AWX API token. demo.sh reads it from .secrets/awx.env."
  sensitive   = true
}

variable "ssh_public_key_file" {
  type        = string
  description = "Public half of the key in AWX's Machine credential. scripts/awx.sh generates it."
  default     = "../.secrets/ansible_ed25519.pub"
}
