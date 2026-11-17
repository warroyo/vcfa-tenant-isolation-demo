#!/usr/bin/env bash
# Installs AWX on the shared services cluster that platform/ built, and sets
# it up for the demo: SSH key, Machine credential, inventory, project and the
# two job templates. Writes AWX_URL and AWX_TOKEN to .secrets/awx.env.
# Safe to run again: it creates only what is missing.
#
# Usage: VCFA_API_TOKEN=... scripts/awx.sh
#   REPO_URL   git URL AWX pulls the playbooks from (default: this repo on GitHub)

source "$(dirname "$0")/env.sh"

REPO_URL=${REPO_URL:-https://github.com/warroyo/vcfa-tenant-isolation-demo.git}
REPO_BRANCH=${REPO_BRANCH:-main}
AWX_OPERATOR_CHART_VERSION=${AWX_OPERATOR_CHART_VERSION:-3.2.1}

out() { terraform -chdir="$REPO_ROOT/platform" output -raw "$1"; }
NAMESPACE=$(out namespace_name)
CLUSTER=$(out awx_cluster_name)

step "Waiting for VKS cluster $CLUSTER in $NAMESPACE"
write_kubeconfig "$(out namespace_host)" "$SECRETS/awx-namespace.kubeconfig"
export KUBECONFIG="$SECRETS/awx-namespace.kubeconfig"
until [[ $(kubectl -n "$NAMESPACE" get cluster "$CLUSTER" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null) == True ]]; do
  sleep 20
done
(umask 077; kubectl -n "$NAMESPACE" get secret "$CLUSTER-kubeconfig" -o jsonpath='{.data.value}' | base64 -d >"$SECRETS/awx-cluster.kubeconfig")
export KUBECONFIG="$SECRETS/awx-cluster.kubeconfig"

step "Installing the AWX operator"
helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/ >/dev/null 2>&1 || true
helm repo update awx-operator >/dev/null
kubectl create namespace awx --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace awx pod-security.kubernetes.io/enforce=privileged --overwrite
helm upgrade --install awx-operator awx-operator/awx-operator -n awx \
  --version "$AWX_OPERATOR_CHART_VERSION" --wait

# Small requests: one demo, two VMs. VKS clusters have no default
# StorageClass, so Postgres names one.
STORAGE_CLASS=$(sed -n 's/^storage_class *= *"\(.*\)"/\1/p' "$REPO_ROOT/platform/lab.auto.tfvars")
kubectl apply -f - <<EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: LoadBalancer
  postgres_storage_class: $STORAGE_CLASS
  postgres_storage_requirements:
    requests:
      storage: 2Gi
  postgres_data_volume_init: true
  web_resource_requirements:
    requests: {cpu: 100m, memory: 256Mi}
  task_resource_requirements:
    requests: {cpu: 100m, memory: 256Mi}
  ee_resource_requirements:
    requests: {cpu: 100m, memory: 128Mi}
  redis_resource_requirements:
    requests: {cpu: 50m, memory: 64Mi}
  rsyslog_resource_requirements:
    requests: {cpu: 50m, memory: 64Mi}
  init_container_resource_requirements:
    requests: {cpu: 50m, memory: 64Mi}
  postgres_resource_requirements:
    requests: {cpu: 100m, memory: 256Mi}
EOF

step "Waiting for AWX (the first start runs database migrations, 5 to 10 minutes)"
until IP=$(kubectl -n awx get svc awx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) && [[ -n $IP ]]; do sleep 10; done
AWX_URL="http://$IP"
until [[ $(curl -s -o /dev/null -w '%{http_code}' "$AWX_URL/api/v2/ping/") == 200 ]]; do sleep 15; done
until kubectl -n awx get secret awx-admin-password >/dev/null 2>&1; do sleep 5; done
ADMIN_PASSWORD=$(kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)
echo "AWX is up at $AWX_URL (user admin; password in secret awx/awx-admin-password)"

api() { # api <method> <path> [json]
  curl -sf -u "admin:$ADMIN_PASSWORD" -X "$1" -H 'Content-Type: application/json' \
    "$AWX_URL/api/v2/$2" ${3:+-d "$3"}
}
# ensure <path> <name> <json>: the id of the named object, created if missing.
ensure() {
  local id
  id=$(api GET "$1?name=$(jq -rn --arg n "$2" '$n|@uri')" | jq -r '.results[0].id // empty')
  [[ -n $id ]] || id=$(api POST "$1" "$3" | jq -r .id)
  echo "$id"
}

step "Setting up AWX"
KEY="$SECRETS/ansible_ed25519"
[[ -f $KEY ]] || ssh-keygen -q -t ed25519 -N '' -C tenant-demo-awx -f "$KEY"

ORG=$(api GET 'organizations/?name=Default' | jq -r '.results[0].id')
MACHINE=$(api GET 'credential_types/?name=Machine&kind=ssh' | jq -r '.results[0].id')

CRED=$(ensure credentials/ tenant-vms "$(jq -n --argjson org "$ORG" --argjson type "$MACHINE" --rawfile key "$KEY" \
  '{name: "tenant-vms", organization: $org, credential_type: $type, inputs: {username: "ansible", ssh_key_data: $key, become_method: "sudo"}}')")
INV=$(ensure inventories/ tenant-vms "$(jq -n --argjson org "$ORG" '{name: "tenant-vms", organization: $org}')")
PROJECT=$(ensure projects/ tenant-demo "$(jq -n --argjson org "$ORG" --arg url "$REPO_URL" --arg branch "$REPO_BRANCH" \
  '{name: "tenant-demo", organization: $org, scm_type: "git", scm_url: $url, scm_branch: $branch}')")

echo "Waiting for the project to sync from $REPO_URL"
api POST "projects/$PROJECT/update/" >/dev/null || true
while :; do
  STATUS=$(api GET "projects/$PROJECT/" | jq -r .status)
  case $STATUS in
    successful) break ;;
    failed | error | canceled) echo "Project sync $STATUS: check that AWX can clone $REPO_URL" >&2; exit 1 ;;
  esac
  sleep 5
done

for t in "Install tenant page:playbooks/tenant-page.yml" "Check isolation:playbooks/isolation-check.yml"; do
  NAME=${t%%:*} PLAYBOOK=${t#*:}
  JT=$(ensure job_templates/ "$NAME" "$(jq -n --arg n "$NAME" --arg p "$PLAYBOOK" --argjson inv "$INV" --argjson proj "$PROJECT" \
    '{name: $n, inventory: $inv, project: $proj, playbook: $p, ask_limit_on_launch: true, ask_variables_on_launch: true}')")
  api POST "job_templates/$JT/credentials/" "{\"id\": $CRED}" >/dev/null 2>&1 || true
  echo "Job template: $NAME ($JT)"
done

if [[ ! -f $SECRETS/awx.env ]] || ! grep -q "AWX_URL=$AWX_URL$" "$SECRETS/awx.env"; then
  TOKEN=$(api POST tokens/ '{"description": "tenant isolation demo", "scope": "write"}' | jq -r .token)
  (umask 077; printf 'AWX_URL=%s\nAWX_TOKEN=%s\n' "$AWX_URL" "$TOKEN" >"$SECRETS/awx.env")
fi
step "Done. AWX_URL and AWX_TOKEN are in .secrets/awx.env"
