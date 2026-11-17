# Sourced by the other scripts. Loads .env (see .env.example), which must set
# TF_VAR_vcfa_api_token, TF_VAR_vcfa_url and TF_VAR_vcfa_org.
#
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SECRETS="$REPO_ROOT/.secrets"
mkdir -p "$SECRETS"
chmod 700 "$SECRETS"

# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/load-env.sh"
for v in TF_VAR_vcfa_api_token TF_VAR_vcfa_url TF_VAR_vcfa_org; do
  [[ -n ${!v:-} ]] || { echo "Set $v in .env (copy .env.example)" >&2; exit 1; }
done
VCFA_URL=$TF_VAR_vcfa_url
VCFA_ORG=$TF_VAR_vcfa_org

# AWX address and token, written by scripts/awx.sh.
if [[ -f "$SECRETS/awx.env" ]]; then
  # shellcheck disable=SC1091
  source "$SECRETS/awx.env"
  export TF_VAR_awx_url="$AWX_URL" TF_VAR_awx_token="$AWX_TOKEN"
fi

# A short-lived VCF Automation access token from the API token.
access_token() {
  curl -sfk -X POST "$VCFA_URL/oauth/tenant/$VCFA_ORG/token" \
    -H 'Accept: application/json' \
    --data-urlencode grant_type=refresh_token \
    --data-urlencode "refresh_token=$TF_VAR_vcfa_api_token" | jq -r .access_token
}

# write_kubeconfig <api address> <file> [namespace]: a kubeconfig for one
# namespace's API. The namespace becomes the context's default.
write_kubeconfig() {
  local host=$1 file=$2 namespace=${3:-} token
  token=$(access_token)
  (umask 077; cat >"$file" <<EOF
apiVersion: v1
kind: Config
clusters: [{name: vcfa, cluster: {server: "$host", insecure-skip-tls-verify: true}}]
users: [{name: vcfa, user: {token: "$token"}}]
contexts: [{name: vcfa, context: {cluster: vcfa, user: vcfa${namespace:+, namespace: \"$namespace\"}}}]
current-context: vcfa
EOF
  )
}

# tenant_kubeconfig <tenant key>: path to a fresh kubeconfig for its namespace.
tenant_kubeconfig() {
  local file="$SECRETS/$1.kubeconfig" tenant
  tenant=$(terraform -chdir="$REPO_ROOT/tenants" output -json tenants | jq -c --arg t "$1" '.[$t]')
  write_kubeconfig "$(jq -r .host <<<"$tenant")" "$file" "$(jq -r .namespace <<<"$tenant")"
  echo "$file"
}

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
