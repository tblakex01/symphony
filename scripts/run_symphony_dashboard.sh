#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
elixir_dir="$repo_root/elixir"
env_file="${SYMPHONY_ENV_FILE:-$repo_root/.env}"
dashboard_port="${SYMPHONY_DASHBOARD_PORT:-4000}"
workflow_file="${SYMPHONY_WORKFLOW_FILE:-../WORKFLOW.md}"

if [ -f "$env_file" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$env_file"
  set +a
  printf '[ok] Loaded environment from %s\n' "$env_file"
fi

export SYMPHONY_WORKSPACE_ROOT="${SYMPHONY_WORKSPACE_ROOT:-$repo_root/symphony-workspaces}"

"$repo_root/scripts/preflight.sh"

if [ "${SYMPHONY_DRY_RUN:-0}" = "1" ]; then
  printf '[ok] Would prepare Elixir runtime in %s\n' "$elixir_dir"
  printf '[ok] Would start Symphony dashboard at http://127.0.0.1:%s/\n' "$dashboard_port"
  printf 'Would start Symphony dashboard: cd %s && mise exec -- ./bin/symphony --i-understand-that-this-will-be-running-without-the-usual-guardrails --port %s %s\n' \
    "$elixir_dir" "$dashboard_port" "$workflow_file"
  exit 0
fi

cd "$elixir_dir"
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build

printf '[ok] Starting Symphony dashboard at http://127.0.0.1:%s/\n' "$dashboard_port"
exec mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --port "$dashboard_port" \
  "$workflow_file"
