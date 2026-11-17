#!/usr/bin/env bash
# Prints every address the demo uses, read live: VCF Automation, AWX, and
# each tenant's VM and load balancer. Run it any time, before or after
# scripts/demo.sh. Nothing here has a DNS name: the load balancers are IPs.
#
# Usage: scripts/endpoints.sh [-p]
#   -p  also print the AWX admin password

source "$(dirname "$0")/env.sh"
SHOW_PASSWORD=false
[[ ${1:-} == -p ]] && SHOW_PASSWORD=true

row() { printf '  %-14s %s\n' "$1" "$2"; }

step "VCF Automation"
row "URL" "$VCFA_URL"
row "Org" "$VCFA_ORG"

step "AWX"
AWX_KC="$SECRETS/awx-cluster.kubeconfig"
awx_ip=""
if [[ -f $AWX_KC ]]; then
  awx_ip=$(kubectl --kubeconfig "$AWX_KC" -n awx get svc awx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
fi
if [[ -n $awx_ip ]]; then
  row "URL" "http://$awx_ip"
  [[ -n ${AWX_URL:-} && $AWX_URL != "http://$awx_ip" ]] && row "Note" "differs from .secrets/awx.env ($AWX_URL): run scripts/awx.sh"
elif [[ -n ${AWX_URL:-} ]]; then
  row "URL" "$AWX_URL (from .secrets/awx.env; the cluster did not answer)"
else
  row "URL" "not installed: run scripts/awx.sh"
fi
row "User" "admin"
if $SHOW_PASSWORD && [[ -f $AWX_KC ]]; then
  row "Password" "$(kubectl --kubeconfig "$AWX_KC" -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)"
else
  row "Password" "scripts/endpoints.sh -p"
fi

step "Tenants"
if ! TENANTS=$(terraform -chdir="$REPO_ROOT/tenants" output -json tenants 2>/dev/null | jq -r 'keys[]') || [[ -z $TENANTS ]]; then
  echo "  None: run scripts/demo.sh"
  exit 0
fi
for t in $TENANTS; do
  kc=$(tenant_kubeconfig "$t")
  k() { kubectl --kubeconfig "$kc" "$@" 2>/dev/null || true; }
  info=$(terraform -chdir="$REPO_ROOT/tenants" output -json tenants | jq -c --arg t "$t" '.[$t]')
  vip=$(k get vmservice "$t-web" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "  $t"
  row "Page" "${vip:+http://$vip}"
  row "VM IP" "$(k get vm "$t-web" -o jsonpath='{.status.network.primaryIP4}')"
  row "Project" "$(jq -r .project <<<"$info")"
  row "Namespace" "$(jq -r .namespace <<<"$info")"
  row "VPC" "$(jq -r .vpc <<<"$info")"
done
