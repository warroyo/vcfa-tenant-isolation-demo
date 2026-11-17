#!/usr/bin/env bash
# The demo: Terraform builds both tenants, AWX configures their VMs, then the
# isolation check runs. DEMO_PAUSE=0 runs it without stopping between steps.
#
# Usage: VCFA_API_TOKEN=... scripts/demo.sh

source "$(dirname "$0")/env.sh"
[[ -n ${AWX_URL:-} ]] || { echo "No .secrets/awx.env: run scripts/awx.sh first" >&2; exit 1; }
pause() { [[ ${DEMO_PAUSE:-1} == 0 ]] || read -rp $'\n[Enter] '; }

step "1. Terraform: two projects, two VPCs, two namespaces, two VMs, and the firewall between them"
pause
terraform -chdir="$REPO_ROOT/tenants" init -input=false >/dev/null
terraform -chdir="$REPO_ROOT/tenants" apply -input=false -auto-approve

step "2. The VMs boot, and AWX configures each one through its namespace's AnsibleBinding"
TENANTS=$(terraform -chdir="$REPO_ROOT/tenants" output -json tenants | jq -r 'keys[]')
declare -A KC
for t in $TENANTS; do KC[$t]=$(tenant_kubeconfig "$t"); done
while :; do
  done_count=0
  for t in $TENANTS; do
    k() { kubectl --kubeconfig "${KC[$t]}" "$@" 2>/dev/null; }
    ip=$(k get vm "$t-web" -o jsonpath='{.status.network.primaryIP4}')
    phase=$(k get ansiblebindingvms -o jsonpath='{.items[0].status.phase}')
    vip=$(k get vmservice "$t-web" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    printf '%-10s vm ip: %-14s ansible: %-10s vip: %s\n' "$t" "${ip:--}" "${phase:-waiting}" "${vip:--}"
    [[ $phase == Succeeded && -n $vip ]] && done_count=$((done_count + 1))
    [[ $phase == Failed ]] && { echo "AWX job failed for $t: see the AnsibleBindingVM and the job in AWX" >&2; exit 1; }
  done
  [[ $done_count == $(wc -w <<<"$TENANTS") ]] && break
  sleep 15; echo
done

step "3. Each tenant's page, through its own load balancer"
for t in $TENANTS; do
  vip=$(kubectl --kubeconfig "${KC[$t]}" get vmservice "$t-web" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "$t: http://$vip  ($(curl -s -m 5 "http://$vip/" | sed -n 's:.*<title>\(.*\)</title>.*:\1:p'))"
done
pause

step "4. Isolation: each tenant's VM tries to reach the other's"
"$REPO_ROOT/scripts/check-isolation.sh"
