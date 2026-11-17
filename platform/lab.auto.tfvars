# Values for the GPU lab's acme org. Nothing secret: the API token comes from
# TF_VAR_vcfa_api_token.

vcfa_url = "https://auto.gpu.set.lab"
vcfa_org = "acme"

region_name                    = "ans-cluster"
zone_name                      = "west-1"
storage_class                  = "vsan-default-storage-policy"
content_library_storage_policy = "vSAN Default Storage Policy"
seg_name                       = "default-se-group"
vpc_connectivity_profile       = "default--ans-cluster"

# Custom 3 vCPU / 6Gi best-effort class for the worker, created by hand in vCenter for this lab.
awx_cluster = { worker_class = "best-effort-awx-worker" }
