# Exports the repo's .env (copied from .env.example). Sourced by env.sh, and
# safe to source in your own shell before running terraform by hand:
#   source scripts/load-env.sh
# A no-op when .env is absent.
#
# shellcheck shell=bash disable=SC1091

_env_file="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/.env"
if [ -f "$_env_file" ]; then
  set -a
  . "$_env_file"
  set +a
fi
unset _env_file
