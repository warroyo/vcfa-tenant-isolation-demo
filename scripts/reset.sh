#!/usr/bin/env bash
# Removes both tenants. platform/ and AWX stay, ready for the next run.
#
# Usage: VCFA_API_TOKEN=... scripts/reset.sh

source "$(dirname "$0")/env.sh"
terraform -chdir="$REPO_ROOT/tenants" destroy -input=false -auto-approve
rm -f "$SECRETS"/tenant-*.kubeconfig
