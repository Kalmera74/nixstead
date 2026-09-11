#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOST_NAME="${1:-${NIXSTEAD_HOST:-}}"
SECRETS_DIR="${2:-${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}}"
SECRETS_FILE="${SECRETS_DIR}/${HOST_NAME}.yaml"
DETAILS_ONLY="${NIXSTEAD_DETAILS_ONLY:-false}"

status=0

usage() {
  cat <<'EOF'
Usage: dev-healthcheck.sh [host_name] [secrets_dir]

Checks enabled services under nixstead.services.dev using the selected NixOS
configuration and its centralized devdb secret file.
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
    status=1
  else
    echo "[ OK ] Command available: ${command_name}"
  fi
}

resolve_rabbitmqctl() {
  local command_path=""
  local exec_start=""
  local package_root=""
  local candidate=""

  command_path="$(command -v rabbitmqctl 2>/dev/null || true)"
  if [[ -n "${command_path}" ]]; then
    printf '%s' "${command_path}"
    return 0
  fi

  exec_start="$(systemctl show rabbitmq.service --property=ExecStart --value 2>/dev/null || true)"
  if [[ ! "${exec_start}" =~ path=([^[:space:];]+) ]]; then
    return 1
  fi

  package_root="${BASH_REMATCH[1]%/*}"
  package_root="${package_root%/*}"
  for candidate in "${package_root}/sbin/rabbitmqctl" "${package_root}/bin/rabbitmqctl"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  return 1
}

check_path() {
  local path="$1"
  local label="$2"
  if [[ -e "${path}" ]]; then
    echo "[ OK ] ${label}: ${path}"
  else
    echo "[WARN] ${label} missing: ${path}"
  fi
}

check_enabled_toggle() {
  local option_path="$1"
  nixstead_config_enabled "${option_path}"
}

print_option() {
  local option_path="$1"
  local label="$2"
  local value
  value="$(nixstead_config_raw "${option_path}" 2>/dev/null || true)"
  if [[ -n "${value}" ]]; then
    echo "[ OK ] ${label}: ${value}"
  else
    echo "[WARN] ${label}: unavailable"
  fi
}

option_exists() {
  local option_path="$1"
  nixstead_config_json "${option_path}" >/dev/null 2>&1
}

option_is_non_null() {
  local option_path="$1"
  local value
  value="$(nixstead_config_json "${option_path}" 2>/dev/null || true)"
  [[ -n "${value}" && "${value}" != "null" ]]
}

get_dev_secret() {
  local service_name="$1"
  local field_name="$2"
  local default_value="$3"

  if [[ -f "${SECRETS_FILE}" ]]; then
    local value
    value="$(sops decrypt --extract "[\"devdb\"][\"${service_name}\"][\"${field_name}\"]" "${SECRETS_FILE}" 2>/dev/null || true)"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
  fi

  printf '%s' "${default_value}"
}

check_systemd_service() {
  local unit_name="$1"
  local load_state
  load_state="$(systemctl show "${unit_name}" --property=LoadState --value 2>/dev/null || true)"

  if [[ -z "${load_state}" || "${load_state}" == "not-found" ]]; then
    echo "[FAIL] Service unit not installed: ${unit_name}"
    status=1
  elif systemctl is-active --quiet "${unit_name}"; then
    echo "[ OK ] Service active: ${unit_name}"
  else
    echo "[FAIL] Service installed but not active: ${unit_name}"
    status=1
  fi
}

echo "==> Running dev service healthcheck for host: ${HOST_NAME}"
echo "==> Repo: ${REPO_ROOT}"
echo "==> Secrets: ${SECRETS_DIR}"

require_cmd nix
require_cmd systemctl
require_cmd ss
require_cmd timeout
require_cmd awk
require_cmd grep
require_cmd jq
require_cmd sops

if [[ "${status}" -ne 0 ]]; then
  echo "==> Dev service healthcheck failed before Nix evaluation."
  exit 1
fi

registry_json="$(nixstead_config_json nixstead.serviceRegistry)"
RABBITMQCTL=""

if jq -e '.redis.enabled' <<<"${registry_json}" >/dev/null; then
  require_cmd redis-cli
fi

if jq -e '.rabbitmq.enabled' <<<"${registry_json}" >/dev/null; then
  if RABBITMQCTL="$(resolve_rabbitmqctl)"; then
    echo "[ OK ] Command available: rabbitmqctl (${RABBITMQCTL})"
  else
    echo "[FAIL] Could not resolve rabbitmqctl from PATH or rabbitmq.service"
    status=1
  fi
fi

if jq -e '.postgresql.enabled' <<<"${registry_json}" >/dev/null; then
  require_cmd psql
fi

if jq -e '.mongodb.enabled' <<<"${registry_json}" >/dev/null; then
  require_cmd mongosh
fi

if [[ "${status}" -ne 0 ]]; then
  echo "==> Dev service healthcheck failed before runtime checks."
  exit 1
fi

check_path "${SECRETS_FILE}" "Encrypted host secrets"

while IFS=$'\x1f' read -r service enabled toggle_path unit port_value; do
  [[ -n "${service}" ]] || continue
  if [[ "${enabled}" == "true" ]]; then
    if [[ "${DETAILS_ONLY}" != true ]]; then
      echo "[ OK ] Toggle enabled: ${toggle_path}"
      check_systemd_service "${unit}"

      if [[ -n "${port_value}" ]]; then
        if ss -ltn | awk '{print $4}' | grep -Eq "(^|:)${port_value}$"; then
          echo "[ OK ] Port listening: ${port_value} (${service})"
        else
          echo "[FAIL] Port not listening: ${port_value} (${service})"
          status=1
        fi
      else
        echo "[WARN] Could not resolve port for ${service}"
      fi
    fi

    if [[ "${service}" == "redis" ]]; then
      if option_is_non_null "services.redis.servers.\"\".requirePass"; then
        echo "[ OK ] Redis requirePass enabled"
      fi
      if option_exists "services.redis.servers.\"\".settings.aclfile"; then
        print_option "services.redis.servers.\"\".settings.aclfile" "Redis ACL file path"
      fi
    fi

    if [[ "${service}" == "mongodb" ]]; then
      print_option "services.mongodb.enableAuth" "MongoDB auth enabled"
    fi

    if [[ "${service}" == "rabbitmq" ]]; then
      print_option "services.rabbitmq.listenAddress" "RabbitMQ listen address"
    fi

    if [[ "${service}" == "redis" || "${service}" == "rabbitmq" || "${service}" == "postgresql" || "${service}" == "mongodb" ]]; then
      expected_user="root"
      expected_password=""
      configured_user="$(get_dev_secret "${service}" "rootUser" "${expected_user}")"
      configured_password="$(get_dev_secret "${service}" "rootPassword" "${expected_password}")"

      if [[ "${configured_user}" == "${expected_user}" && "${configured_password}" == "${expected_password}" ]]; then
        echo "[WARN] ${service} is using default credentials (${expected_user}/${expected_password:-<empty>})"

        if [[ -z "${port_value}" ]]; then
          echo "[WARN] Skipping default credential auth test for ${service}; port is unavailable"
          continue
        fi

        if [[ "${service}" == "postgresql" ]]; then
          if timeout 5 env PGPASSWORD="${expected_password}" psql -h 127.0.0.1 -p "${port_value}" -U "${expected_user}" -d postgres -c 'SELECT 1' >/dev/null 2>&1; then
            echo "[FAIL] Default credentials authenticate successfully for ${service}"
            status=1
          else
            echo "[ OK ] Default credentials rejected for ${service}"
          fi
        fi

        if [[ "${service}" == "mongodb" ]]; then
          if timeout 5 mongosh --quiet --host 127.0.0.1 --port "${port_value}" --authenticationDatabase admin -u "${expected_user}" -p "${expected_password}" --eval 'db.runCommand({ ping: 1 })' >/dev/null 2>&1; then
            echo "[FAIL] Default credentials authenticate successfully for ${service}"
            status=1
          else
            echo "[ OK ] Default credentials rejected for ${service}"
          fi
        fi

        if [[ "${service}" == "redis" ]]; then
          if timeout 5 redis-cli -h 127.0.0.1 -p "${port_value}" --user "${expected_user}" --pass "${expected_password}" ping >/dev/null 2>&1; then
            echo "[FAIL] Default credentials authenticate successfully for ${service}"
            status=1
          else
            echo "[ OK ] Default credentials rejected for ${service}"
          fi
        fi

        if [[ "${service}" == "rabbitmq" ]]; then
          if timeout 5 "${RABBITMQCTL}" authenticate_user "${expected_user}" "${expected_password}" >/dev/null 2>&1; then
            echo "[FAIL] Default credentials authenticate successfully for ${service}"
            status=1
          else
            echo "[ OK ] Default credentials rejected for ${service}"
          fi
        fi
      else
        echo "[ OK ] ${service} credentials differ from defaults"
      fi
    fi
  else
    echo "[INFO] Toggle disabled: ${toggle_path} (skipping runtime checks)"
  fi
done < <(
  jq -r '
    to_entries[]
    | select(.value.health.devDetailed // false)
    | [
        .key,
        .value.enabled,
        ("nixstead.services." + (.value.enablePath | join("."))),
        .value.health.unit,
        (.value.settings.port // "")
      ]
    | join("\u001f")
  ' <<<"${registry_json}"
)

if [[ "${status}" -ne 0 ]]; then
  echo "==> Dev service healthcheck failed."
  exit 1
fi

echo "==> Dev service healthcheck passed."
