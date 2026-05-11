#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
elixir_dir="$repo_root/elixir"
dashboard_port="${SYMPHONY_DASHBOARD_PORT:-4000}"
env_file="${SYMPHONY_ENV_FILE:-$repo_root/.env}"

ok() {
  printf '[ok] %s\n' "$1"
}

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

load_env_file() {
  if [ -f "$env_file" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
    ok "Loaded environment from $env_file"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required command '$1' is not available in PATH"
  fi
}

github_repo_from_url() {
  local url="$1"
  local path=""

  case "$url" in
    https://github.com/*) path="${url#https://github.com/}" ;;
    git@github.com:*) path="${url#git@github.com:}" ;;
    ssh://git@github.com/*) path="${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac

  path="${path%%\?*}"
  path="${path%%#*}"
  path="${path%.git}"

  local owner="${path%%/*}"
  local repo="${path#*/}"
  repo="${repo%%/*}"

  if [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$repo" ]; then
    return 1
  fi

  printf '%s/%s\n' "$owner" "$repo"
}

check_linear() {
  if [ -z "${LINEAR_API_KEY:-}" ]; then
    fail "LINEAR_API_KEY is not exported. Put it in .env or export it before starting Symphony."
  fi

  {
    printf '%s\n' 'request = "POST"'
    printf '%s\n' 'url = "https://api.linear.app/graphql"'
    printf '%s\n' 'header = "Content-Type: application/json"'
    printf '%s\n' "header = \"Authorization: $LINEAR_API_KEY\""
    printf '%s\n' 'data = "{\"query\":\"query { viewer { id name } }\"}"'
  } | {
    local response
    if ! response="$(curl --silent --show-error --fail --config -)"; then
      fail "Linear API verification failed. Confirm LINEAR_API_KEY is valid."
    fi

    if [[ "$response" != *'"viewer"'* ]]; then
      fail "Linear API verification did not return viewer data."
    fi
  }

  ok "Linear API key verified"
}

check_git_and_github() {
  local actual_root
  actual_root="$(git -C "$repo_root" rev-parse --show-toplevel)"
  [ "$actual_root" = "$repo_root" ] || fail "Script resolved $repo_root, but git root is $actual_root"

  local origin_url origin_repo upstream_url upstream_repo
  origin_url="$(git -C "$repo_root" remote get-url origin)"
  origin_repo="$(github_repo_from_url "$origin_url")" || fail "origin must be a GitHub remote, got: $origin_url"

  if [ "$origin_repo" = "openai/symphony" ]; then
    fail "origin points to openai/symphony. Set origin to a writable fork before running autonomous workers."
  fi

  upstream_url="$(git -C "$repo_root" remote get-url upstream 2>/dev/null || true)"
  if [ -n "$upstream_url" ]; then
    upstream_repo="$(github_repo_from_url "$upstream_url")" || fail "upstream must be a GitHub remote, got: $upstream_url"
    [ "$upstream_repo" = "openai/symphony" ] || fail "upstream should point to openai/symphony, got: $upstream_repo"
  fi

  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    fail "GitHub authentication is unavailable. Run gh auth login, then rerun the helper."
  fi

  gh repo view "$origin_repo" --json nameWithOwner --jq .nameWithOwner >/dev/null
  git -C "$repo_root" ls-remote --exit-code origin HEAD >/dev/null

  if [ "${SYMPHONY_PREFLIGHT_SKIP_PUSH_DRY_RUN:-0}" != "1" ]; then
    local branch="refs/heads/symphony-preflight-${USER:-user}-$$"
    if ! git -C "$repo_root" push --dry-run origin "HEAD:$branch" >/dev/null 2>&1; then
      fail "GitHub push dry run failed. Confirm origin is writable and Git credentials are configured."
    fi
  fi

  ok "GitHub auth and writable fork access verified for $origin_repo"
}

check_mise() {
  mise --version >/dev/null

  local trust_output
  trust_output="$(cd "$elixir_dir" && mise trust --show 2>&1 || true)"

  if [[ "$trust_output" != *trusted* ]]; then
    fail "mise config is not trusted for $elixir_dir. Run: cd elixir && mise trust"
  fi

  ok "mise is available and the Elixir config is trusted"
}

check_dashboard_port() {
  if command -v lsof >/dev/null 2>&1; then
    if lsof -tiTCP:"$dashboard_port" -sTCP:LISTEN >/dev/null 2>&1; then
      fail "Dashboard port $dashboard_port is already in use. Stop that process or set SYMPHONY_DASHBOARD_PORT."
    fi
  fi

  ok "Dashboard port $dashboard_port is available"
}

check_workflow_contract() {
  if ! grep -q 'networkAccess: true' "$repo_root/WORKFLOW.md"; then
    fail "WORKFLOW.md must enable codex.turn_sandbox_policy.networkAccess for autonomous PR publishing."
  fi

  if ! grep -q 'writableRoots:' "$repo_root/WORKFLOW.md"; then
    fail "WORKFLOW.md must set codex.turn_sandbox_policy.writableRoots."
  fi

  ok "WORKFLOW.md includes the autonomous worker sandbox contract"
}

main() {
  load_env_file

  export SYMPHONY_WORKSPACE_ROOT="${SYMPHONY_WORKSPACE_ROOT:-$repo_root/symphony-workspaces}"

  require_command git
  require_command gh
  require_command curl
  require_command mise

  check_linear
  check_git_and_github
  check_mise
  check_dashboard_port
  check_workflow_contract

  ok "Preflight passed"
}

main "$@"
