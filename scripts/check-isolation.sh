#!/usr/bin/env bash
# From each tenant's VM, tries to reach the other tenant's VM on 22 and 80,
# through an AnsibleRun and the "Check isolation" job template. Prints BLOCKED
# when the firewall holds.
#
# Usage: VCFA_API_TOKEN=... scripts/check-isolation.sh

source "$(dirname "$0")/env.sh"
read -r A B < <(terraform -chdir="$REPO_ROOT/tenants" output -json tenants | jq -r 'keys | join(" ")')
KA=$(tenant_kubeconfig "$A"); KB=$(tenant_kubeconfig "$B")
ip() { kubectl --kubeconfig "$1" get vm "$2-web" -o jsonpath='{.status.network.primaryIP4}'; }

check() { # check <from tenant> <its kubeconfig> <target ip>
  local run
  run=$(kubectl --kubeconfig "$2" create -o name -f - <<YAML
apiVersion: field.vmware.com/v1
kind: AnsibleRun
metadata:
  generateName: isolation-check-
spec:
  awxConnectionRef: awx
  template: {name: Check isolation, type: JobTemplate}
  vmRef: {name: $1-web}
  extraVars: {target_ip: "$3"}
  activeDeadlineSeconds: 300
  ttlSecondsAfterFinished: 900
YAML
)
  local state
  until state=$(kubectl --kubeconfig "$2" get "$run" -o jsonpath='{.status.state}') && [[ $state == Ready || $state == Failed ]]; do sleep 5; done
  local url; url=$(kubectl --kubeconfig "$2" get "$run" -o jsonpath='{.status.jobURL}')
  if [[ $state == Ready ]]; then echo "BLOCKED  $1 -> $3   (AWX job: $url)"; else echo "REACHED  $1 -> $3   (AWX job: $url)"; fi
}

check "$A" "$KA" "$(ip "$KB" "$B")"
check "$B" "$KB" "$(ip "$KA" "$A")"
