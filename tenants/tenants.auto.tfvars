# Values for the GPU lab's acme org. Nothing secret: the API tokens come from
# environment variables (see scripts/env.sh).

vcfa_url = "https://auto.gpu.set.lab"
vcfa_org = "acme"

region_name              = "ans-cluster"
zone_name                = "west-1"
storage_class            = "vsan-default-storage-policy"
seg_name                 = "default-se-group"
vpc_connectivity_profile = "default--ans-cluster"
vip_range                = "10.47.7.41-10.47.7.141"

tenants = {
  tenant-a = {
    display_name = "Tenant A"
    color        = "#1d6fd8"
    cidr         = "10.10.0.0/24"
  }
  tenant-b = {
    display_name = "Tenant B"
    color        = "#d8691d"
    cidr         = "10.20.0.0/24"
  }
}
