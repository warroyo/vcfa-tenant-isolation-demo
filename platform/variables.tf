# --- VCF Automation ---

variable "vcfa_url" {
  type        = string
  description = "VCF Automation URL."
}

variable "vcfa_org" {
  type        = string
  description = "The org the demo runs in."
}

variable "vcfa_api_token" {
  type        = string
  description = "An Organization Administrator's API token. Set it with TF_VAR_vcfa_api_token, never in a file."
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
  description = "Storage class for the namespace and the cluster, by its Kubernetes name."
}

variable "content_library_storage_policy" {
  type        = string
  description = "Storage policy for the content library, by its name in vCenter. The org's region quota must include it."
}

variable "seg_name" {
  type        = string
  description = "Avi Service Engine Group. Required in a region that uses Avi."
}

variable "vpc_connectivity_profile" {
  type        = string
  description = "VPC connectivity profile the shared services VPC attaches to."
}

# --- Shared services ---

variable "name" {
  type        = string
  description = "Name of the shared services project and VPC."
  default     = "shared-services"
}

variable "vpc_cidr" {
  type        = string
  description = "Private CIDR of the shared services VPC."
  default     = "10.90.0.0/24"
}

variable "awx_cluster" {
  type = object({
    name                = optional(string, "awx")
    class               = optional(string, "builtin-generic-v3.8.0")
    version             = optional(string, "v1.36.1+vmware.4")
    control_plane_class = optional(string, "best-effort-small")
    worker_class        = optional(string, "best-effort-medium")
  })
  description = "The VKS cluster AWX runs on: one control plane node and one worker, the smallest that fits AWX."
  default     = {}
}

variable "ubuntu_image" {
  type = object({
    name = optional(string, "ubuntu-24.04-cloud")
    url  = optional(string, "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.ova")
  })
  description = "The Ubuntu cloud image the tenant VMs boot from."
  default     = {}
}
