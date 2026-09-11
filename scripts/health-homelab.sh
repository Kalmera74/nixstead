#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
HOST_NAME="${1:-${NIXSTEAD_HOST:-}}"
SECRETS_DIR="${2:-${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}}"
status=0

usage() {
  cat <<'EOF'
Usage: nixstead [--host <name>] [--secrets-dir <path>] check runtime

Checks the runtime state selected by the host's typed Nix configuration:
- enabled CIFS mounts
- configured network infrastructure
- enabled systemd services
- local service ports and HTTP endpoints

Examples:
  nixstead check runtime
  nixstead --host arr check runtime
  nixstead --host myhost --secrets-dir /path/to/secrets check runtime
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

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "[FAIL] Missing command: ${command_name}"
    status=1
  else
    echo "[ OK ] Command available: ${command_name}"
  fi
}

check_required_path() {
  local path="$1"
  local label="$2"
  if [[ -e "${path}" ]]; then
    echo "[ OK ] ${label}: ${path}"
  else
    echo "[FAIL] ${label} missing: ${path}"
    status=1
  fi
}

check_optional_path() {
  local path="$1"
  local label="$2"
  if [[ -e "${path}" ]]; then
    echo "[ OK ] ${label}: ${path}"
  else
    echo "[WARN] ${label} missing: ${path}"
  fi
}

check_mount() {
  local path="$1"
  local label="$2"
  if mountpoint -q "${path}"; then
    echo "[ OK ] Mount active: ${label} (${path})"
  else
    echo "[FAIL] Mount not active: ${label} (${path})"
    status=1
  fi
}

check_ping() {
  local ip="$1"
  local label="$2"
  [[ -n "${ip}" ]] || return 0

  if timeout 3 ping -c 1 -W 2 "${ip}" >/dev/null 2>&1; then
    echo "[ OK ] Reachable: ${label} (${ip})"
  else
    echo "[WARN] Unreachable: ${label} (${ip})"
  fi
}

check_http_any_response() {
  local url="$1"
  local label="$2"
  local code
  code="$(curl -ksS --max-time 5 -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"

  if [[ -n "${code}" && "${code}" != "000" ]]; then
    echo "[ OK ] HTTP reachable: ${label} (${url}) -> ${code}"
  else
    echo "[WARN] HTTP unreachable: ${label} (${url})"
  fi
}

check_local_endpoint() {
  local port="$1"
  local label="$2"
  local protocol="${3:-http}"

  [[ -n "${port}" ]] || return 0

  if ss -ltn | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then
    echo "[ OK ] Port listening: ${label} (${port})"
  else
    echo "[FAIL] Port not listening: ${label} (${port})"
    status=1
    return
  fi

  if [[ "${protocol}" == "http" ]]; then
    check_http_any_response "http://127.0.0.1:${port}" "${label}"
  fi
}

service_enabled() {
  local jq_filter="$1"
  jq -e "(${jq_filter}) == true" <<<"${services_json}" >/dev/null
}

service_value() {
  local jq_filter="$1"
  jq -r "${jq_filter} // empty" <<<"${services_json}"
}

host_value() {
  local jq_filter="$1"
  jq -r "${jq_filter} // empty" <<<"${host_json}"
}

check_systemd_service() {
  local unit_name="$1"
  local label="$2"
  local load_state
  load_state="$(systemctl show "${unit_name}" --property=LoadState --value 2>/dev/null || true)"

  if [[ -z "${load_state}" || "${load_state}" == "not-found" ]]; then
    echo "[FAIL] Service unit missing: ${unit_name} (${label})"
    status=1
    return
  fi

  if systemctl is-active --quiet "${unit_name}"; then
    echo "[ OK ] Service active: ${unit_name} (${label})"
  else
    echo "[FAIL] Service installed but inactive: ${unit_name} (${label})"
    status=1
  fi
}

echo "==> Running homelab healthcheck for host: ${HOST_NAME}"
for command_name in jq systemctl ss curl ping timeout mountpoint awk grep; do
  require_cmd "${command_name}"
done

if [[ "${status}" -ne 0 ]]; then
  echo "==> Homelab healthcheck failed before loading configuration metadata."
  exit 1
fi

if [[ -n "${NIXSTEAD_SERVICES_FILE:-}" || -n "${NIXSTEAD_REGISTRY_FILE:-}" || -n "${NIXSTEAD_HOST_FILE:-}" ]]; then
  for metadata_file in "${NIXSTEAD_SERVICES_FILE:-}" "${NIXSTEAD_REGISTRY_FILE:-}" "${NIXSTEAD_HOST_FILE:-}"; do
    [[ -n "${metadata_file}" && -r "${metadata_file}" ]] || {
      echo "[FAIL] Runtime configuration metadata is incomplete or unreadable: ${metadata_file:-<unset>}"
      exit 1
    }
  done
  services_json="$(<"${NIXSTEAD_SERVICES_FILE}")"
  registry_json="$(<"${NIXSTEAD_REGISTRY_FILE}")"
  host_json="$(<"${NIXSTEAD_HOST_FILE}")"
  echo "[ OK ] Loaded immutable runtime configuration metadata."
else
  echo "==> Repo: ${REPO_ROOT}"
  echo "==> Secrets: ${SECRETS_DIR}"
  require_cmd nix
  check_required_path "${REPO_ROOT}/flake.nix" "Flake file"
  if [[ "${status}" -ne 0 ]]; then
    echo "==> Homelab healthcheck failed before Nix evaluation."
    exit 1
  fi
  # shellcheck source=scripts/lib/nixstead.sh
  # shellcheck disable=SC1091
  source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
  if ! services_json="$(nixstead_config_json nixstead.services)" ||
    ! registry_json="$(nixstead_config_json nixstead.serviceRegistry)" ||
    ! host_json="$(nixstead_config_json nixstead.host)"; then
    echo "[FAIL] Could not evaluate NixOS configuration: ${HOST_NAME}"
    exit 1
  fi
  echo "[ OK ] NixOS configuration evaluates: ${HOST_NAME}"
fi

if service_enabled '.cifs.enable'; then
  cifs_credentials_file="$(service_value '.cifs.credentialsFile')"
  if [[ "${EUID}" -eq 0 ]]; then
    check_required_path "${cifs_credentials_file}" "Runtime CIFS credentials"
  else
    echo "[INFO] Runtime CIFS credentials are root-only: ${cifs_credentials_file}"
  fi

  while IFS=$'\t' read -r share_name mount_point; do
    [[ -n "${mount_point}" ]] || continue
    check_mount "${mount_point}" "CIFS ${share_name}"
  done < <(jq -r '.cifs.shares | to_entries[] | select(.value != null) | [.key, .value.mountPoint] | @tsv' <<<"${services_json}")
fi

check_ping "$(host_value '.network.router')" "Router"
check_ping "$(host_value '.network.switch')" "Switch"

while IFS=$'\x1f' read -r service_id label unit protocol port ip external suffix host_port; do
  [[ -n "${service_id}" ]] || continue

  if [[ -n "${host_port}" ]]; then
    port="$(host_value ".ports.${host_port}")"
  fi

  if [[ "${external}" == "true" ]]; then
    check_ping "${ip}" "${label}"
    if [[ -n "${ip}" && -n "${port}" ]]; then
      check_http_any_response "${protocol}://${ip}:${port}${suffix}" "${label}"
    fi
    continue
  fi

  if [[ -n "${unit}" ]]; then
    check_systemd_service "${unit}" "${label}"
  fi
  if [[ "${protocol}" != "none" ]]; then
    check_local_endpoint "${port}" "${label}" "${protocol}"
  fi
done < <(
  jq -r '
    to_entries[]
    | select(.value.enabled and .value.health != null)
    | [
        .key,
        .value.name,
        (.value.health.unit // ""),
        (.value.health.protocol // "http"),
        (.value.settings.port // ""),
        (.value.settings.ip // ""),
        (.value.health.external // false),
        (.value.health.suffix // ""),
        (.value.health.hostPort // "")
      ]
    | join("\u001f")
  ' <<<"${registry_json}"
)

if jq -e '.kiwix.enabled' <<<"${registry_json}" >/dev/null; then
  check_optional_path "$(jq -r '.kiwix.settings.paths.basePath' <<<"${registry_json}")" "Kiwix library directory"
  check_optional_path "$(jq -r '.kiwix.settings.paths.libraryPath' <<<"${registry_json}")" "Kiwix library file"
fi

if [[ "${status}" -ne 0 ]]; then
  echo "==> Homelab healthcheck failed."
  exit 1
fi

echo "==> Homelab healthcheck passed."
