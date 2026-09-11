#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOST_NAME="${1:-${NIXSTEAD_HOST:-}}"
SECRETS_DIR="${2:-${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}}"
SECRETS_FILE="${SECRETS_DIR}/${HOST_NAME}.yaml"
status=0

usage() {
  cat <<'EOF'
Usage: nixstead [--host <name>] [--secrets-dir <path>] check preflight

Runs the non-destructive preflight checks used before a rebuild. Requirements
are derived from the selected NixOS configuration, so disabled services do not
require their mounts, units, or secrets.

Examples:
  nixstead check preflight
  nixstead --host minimal check preflight
  nixstead --host myhost --secrets-dir /path/to/secrets check preflight
EOF
}

if [[ "${HOST_NAME}" == "-h" || "${HOST_NAME}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 2 ]]; then
  printf 'Error: too many arguments.\n' >&2
  usage
  exit 1
fi

# shellcheck source=scripts/lib/nixstead.sh
source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
nixstead_config_validate_context

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "[FAIL] Missing command: ${command_name}"
    return 1
  fi
  echo "[ OK ] Command available: ${command_name}"
}

check_path() {
  local path="$1"
  local label="$2"
  if [[ -e "${path}" ]]; then
    echo "[ OK ] ${label}: ${path}"
  else
    echo "[FAIL] ${label} missing: ${path}"
    return 1
  fi
}

echo "==> Running healthcheck for host: ${HOST_NAME}"
echo "==> Repo: ${REPO_ROOT}"
echo "==> Secrets: ${SECRETS_DIR}"

require_cmd nix || status=1
require_cmd jq || status=1

check_path "${REPO_ROOT}/flake.nix" "Flake file" || status=1

if [[ "${status}" -ne 0 ]]; then
  echo "==> Healthcheck failed before Nix evaluation."
  exit 1
fi

if ! registry_json="$(nixstead_config_json nixstead.serviceRegistry)"; then
  echo "[FAIL] Could not evaluate services for NixOS configuration: ${HOST_NAME}"
  exit 1
fi
echo "[ OK ] NixOS configuration exists: ${HOST_NAME}"

required_secrets="$(
  jq -r '[to_entries[] | select(.value.enabled) | .value.secrets[]] | unique[]' <<<"${registry_json}"
)"

if [[ -n "${required_secrets}" ]]; then
  require_cmd sops || status=1
  check_path "${SECRETS_FILE}" "Encrypted host secrets" || status=1

  if [[ "${status}" -eq 0 ]]; then
    if sops filestatus "${SECRETS_FILE}" | jq -e '.encrypted == true' >/dev/null; then
      echo "[ OK ] SOPS file is encrypted: ${SECRETS_FILE}"
    else
      echo "[FAIL] SOPS file is not encrypted: ${SECRETS_FILE}"
      status=1
    fi

    while IFS= read -r secret_name; do
      [[ -n "${secret_name}" ]] || continue
      if sops decrypt --extract "[\"${secret_name}\"]" "${SECRETS_FILE}" >/dev/null 2>&1; then
        echo "[ OK ] Encrypted secret branch: ${secret_name}"
      else
        echo "[FAIL] Missing encrypted secret branch: ${secret_name}"
        status=1
      fi
    done <<<"${required_secrets}"
  fi
fi

if toplevel_drv="$(nixstead_config_raw system.build.toplevel.drvPath)"; then
  echo "[ OK ] System closure evaluates: ${toplevel_drv}"
else
  echo "[FAIL] System closure does not evaluate: ${HOST_NAME}"
  status=1
fi

if [[ "${status}" -ne 0 ]]; then
  echo "==> Healthcheck failed. Fix failing items before setup/rebuild."
  exit 1
fi

echo "==> Healthcheck passed."
