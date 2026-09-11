#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CONFIGS_DIR="${NIXSTEAD_BACKUP_STATE_DIR:-${REPO_ROOT}/Configs}"
BORG_REPO="${NIXSTEAD_BACKUP_REPOSITORY:-${CONFIGS_DIR}/borg-service-data}"
LATEST_DIR="${CONFIGS_DIR}/service-configs-latest"
RESTORE_MODE=""
ARCHIVE_NAME=""
RESTART_SERVICES=false
RESTORE_DATABASES=false
APPLY=false
RESTORE_MUTATED=false
TMP_RESTORE_DIR=""
DATABASE_DUMP_DIR=""
HOST_NAME="${NIXSTEAD_HOST:-}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
export HOST_NAME SECRETS_DIR
# shellcheck source=scripts/lib/service-databases.sh
# shellcheck disable=SC1091
source "${NIXSTEAD_DATABASE_LIB:-${SCRIPT_DIR}/lib/service-databases.sh}"

usage() {
  cat <<EOF
Usage:
  nixstead backup restore latest --apply [--restart-services] [--restore-databases]
  nixstead backup restore borg <archive-name> --apply [--restart-services] [--restore-databases]

Restores the service configuration directories managed by the matching backup
helper. Restore is refused unless --apply is supplied. Each service is stopped
before its files are changed, and previously running services are started again.
Use --restart-services to also start restored services that were not running.
Database-backed services require --restore-databases to restore their matching
PostgreSQL/MariaDB logical dump or Elasticsearch snapshot. This replaces matching
database objects; Elasticsearch restores only the snapshot's application indices.
Set NIXSTEAD_HOST to select a configuration when using the repository script.
Set NIXSTEAD_BACKUP_REPOSITORY to the same local or remote Borg repository
used for backup.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    latest | borg)
      if [[ -n "${RESTORE_MODE}" ]]; then
        echo "Restore mode already selected: ${RESTORE_MODE}" >&2
        usage >&2
        exit 1
      fi
      RESTORE_MODE="$1"
      shift
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    --restart-services)
      RESTART_SERVICES=true
      shift
      ;;
    --restore-databases)
      RESTORE_DATABASES=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ "${RESTORE_MODE}" == "borg" && -z "${ARCHIVE_NAME}" ]]; then
        ARCHIVE_NAME="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "${RESTORE_MODE}" ]]; then
  echo "A restore mode is required." >&2
  usage >&2
  exit 1
fi

if [[ "${RESTORE_MODE}" == "latest" && -n "${ARCHIVE_NAME}" ]]; then
  echo "latest mode does not accept an archive name." >&2
  exit 1
fi

if [[ "${RESTORE_MODE}" == "borg" && -z "${ARCHIVE_NAME}" ]]; then
  echo "Archive name required for borg mode." >&2
  usage >&2
  exit 1
fi

if [[ "${APPLY}" != true ]]; then
  echo "Restore is destructive; re-run with --apply after verifying the source." >&2
  exit 1
fi

RESTORED_SERVICES=()
STOPPED_UNITS=()

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo) so /var/lib can be restored."
  exit 1
fi

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}"
    exit 1
  fi
}

for command_name in borg chmod chown dirname find grep id jq ln mkdir mktemp readlink rm rsync runuser stat systemctl; do
  require_cmd "${command_name}"
done

if [[ -n "${NIXSTEAD_REGISTRY_FILE:-}" ]]; then
  [[ -r "${NIXSTEAD_REGISTRY_FILE}" ]] || {
    echo "Registry metadata is not readable: ${NIXSTEAD_REGISTRY_FILE}" >&2
    exit 1
  }
  registry_json="$(<"${NIXSTEAD_REGISTRY_FILE}")"
else
  require_cmd nix
  # shellcheck source=scripts/lib/nixstead.sh
  # shellcheck disable=SC1091
  source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
  registry_json="$(nixstead_config_json nixstead.serviceRegistry)"
fi
SERVICES=()
declare -A SERVICE_DIRS=()
declare -A SERVICE_PATHS=()
declare -A SERVICE_OWNER=()
declare -A SERVICE_GROUP=()
declare -A SERVICE_UNITS=()

while IFS=$'\x1f' read -r service directory paths units owner group; do
  [[ -n "${service}" ]] || continue
  SERVICES+=("${service}")
  SERVICE_DIRS["${service}"]="${directory}"
  SERVICE_PATHS["${service}"]="${paths}"
  SERVICE_UNITS["${service}"]="${units}"
  SERVICE_OWNER["${service}"]="${owner}"
  SERVICE_GROUP["${service}"]="${group}"
done < <(
  jq -r '
    to_entries[]
    | select(.value.enabled and .value.backup != null)
    | [.key, .value.backup.directory, (.value.backup.paths | join("|")), (.value.backup.units | join(",")), .value.backup.owner, .value.backup.group]
    | join("\u001f")
  ' <<<"${registry_json}"
)

resolve_target_dir() {
  local service="$1"
  local path_index="$2"
  local configured_paths=()
  IFS='|' read -r -a configured_paths <<<"${SERVICE_PATHS[$service]}"
  local dest="${configured_paths[$path_index]}"

  if jq -e --arg service "${service}" '.[$service].backup.dynamicUser // false' <<<"${registry_json}" >/dev/null; then
    [[ "${dest}" == /var/lib/* && "${dest}" != /var/lib/private/* ]] || {
      echo "Invalid dynamic state path: ${dest}" >&2
      return 1
    }
    local private_dest="/var/lib/private/${dest#/var/lib/}"
    if [[ ! -e "${dest}" && ! -L "${dest}" ]]; then
      mkdir -p "${private_dest}" "$(dirname "${dest}")"
      chmod 0700 /var/lib/private "${private_dest}"
      # Let systemd create its own relative public symlink at startup. An
      # absolute symlink is rejected by StateDirectory's safety checks.
      echo "${private_dest}"
      return
    fi
  fi

  if [[ -L "${dest}" ]]; then
    readlink -f "${dest}"
  else
    echo "${dest}"
  fi
}

resolve_owner_group() {
  local target_dir="$1"
  local service="$2"

  if [[ -e "${target_dir}" ]]; then
    stat -c '%u:%g' "${target_dir}"
    return
  fi

  local owner="${SERVICE_OWNER[$service]:-root}"
  local group="${SERVICE_GROUP[$service]:-root}"

  echo "${owner}:${group}"
}

stop_service_for_restore() {
  local service="$1"
  local units=()
  local unit=""
  IFS=',' read -r -a units <<<"${SERVICE_UNITS[$service]:-}"
  for unit in "${units[@]}"; do
    if [[ -n "${unit}" ]] && systemctl is-active --quiet "${unit}"; then
      systemctl stop "${unit}"
      STOPPED_UNITS+=("${unit}")
      echo "Stopped ${unit} before restoring ${service}."
    fi
  done
}

restart_stopped_units() {
  local failed=false
  local remaining_units=()
  local unit
  local index

  for ((index = ${#STOPPED_UNITS[@]} - 1; index >= 0; index--)); do
    unit="${STOPPED_UNITS[$index]}"
    if systemctl start "${unit}"; then
      echo "Restarted previously running unit ${unit}."
    else
      echo "Failed to restart previously running unit ${unit}." >&2
      failed=true
      remaining_units+=("${unit}")
    fi
  done
  STOPPED_UNITS=("${remaining_units[@]}")

  [[ "${failed}" == "false" ]]
}

cleanup() {
  local exit_code=$?
  trap - EXIT

  if [[ "${exit_code}" -ne 0 && "${RESTORE_MUTATED}" == true ]]; then
    echo "Restore failed after modifying state; automatic restart of remaining stopped units was suppressed. Inspect affected services before recovery." >&2
  elif ! restart_stopped_units; then
    exit_code=1
  fi

  if [[ -n "${TMP_RESTORE_DIR}" && -d "${TMP_RESTORE_DIR}" ]]; then
    rm -rf -- "${TMP_RESTORE_DIR}"
  fi

  exit "${exit_code}"
}
trap cleanup EXIT

restore_service_dir() {
  local service="$1"
  local src_dir="$2"
  local path_index="$3"
  local target_dir
  local owner_group

  target_dir="$(resolve_target_dir "${service}" "${path_index}")"
  owner_group="$(resolve_owner_group "${target_dir}" "${service}")"
  if jq -e --arg service "${service}" '.[$service].backup.dynamicUser // false' <<<"${registry_json}" >/dev/null; then
    # systemd assigns a fresh dynamic identity and fixes ownership at startup.
    owner_group="0:0"
  fi

  mkdir -p "${target_dir}"

  RESTORE_MUTATED=true
  rsync -a --delete "${src_dir}/" "${target_dir}/"
  chown -R "${owner_group}" "${target_dir}"

  if [[ ! " ${RESTORED_SERVICES[*]} " =~ [[:space:]]${service}[[:space:]] ]]; then
    RESTORED_SERVICES+=("${service}")
  fi
  echo "Restored ${service} to ${target_dir} with owner ${owner_group}."
}

restart_restored_services() {
  if [[ "${#RESTORED_SERVICES[@]}" -eq 0 ]]; then
    echo "No services restored; nothing to restart."
    return
  fi

  echo "Restarting restored services..."
  local service
  for service in "${RESTORED_SERVICES[@]}"; do
    local units=()
    local unit=""
    IFS=',' read -r -a units <<<"${SERVICE_UNITS[$service]:-}"
    if [[ "${#units[@]}" -eq 0 ]]; then
      echo "Skipping restart for ${service}; no mapped systemd unit."
      continue
    fi
    local index
    for ((index = ${#units[@]} - 1; index >= 0; index--)); do
      unit="${units[$index]}"
      local load_state
      load_state="$(systemctl show "${unit}" --property=LoadState --value 2>/dev/null || true)"
      if [[ -n "${load_state}" && "${load_state}" != "not-found" ]]; then
        if [[ "${unit}" == "$(database_field "${service}" databaseUnit)" ]]; then
          # Import already started this database. Restarting it here can stop
          # restored applications that depend on a shared PostgreSQL server.
          systemctl start "${unit}"
        else
          systemctl restart "${unit}"
        fi
        echo "Started or restarted ${unit}."
      else
        echo "Skipping ${unit}; unit not installed on this host."
      fi
    done
  done

}

validate_restore_source() {
  local source_root="$1" service path_index src required_file
  local configured_paths=()
  for service in "${SERVICES[@]}"; do
    validate_database_dump "${service}" "${source_root}" || return 1
    case "$(database_field "${service}" database)" in
      postgresql)
        if [[ "$(database_field "${service}" databaseFormat)" == custom ]]; then
          require_cmd pg_restore
        else
          require_cmd psql
        fi
        ;;
      mariadb-container | postgresql-container) require_cmd docker ;;
      elasticsearch-container)
        require_cmd docker
        require_cmd python3
        ;;
    esac
    if [[ -n "$(database_field "${service}" database)" && "${RESTORE_DATABASES}" != true ]]; then
      echo "${service} requires --restore-databases; nothing restored." >&2
      return 1
    fi
    IFS='|' read -r -a configured_paths <<<"${SERVICE_PATHS[$service]}"
    for ((path_index = 0; path_index < ${#configured_paths[@]}; path_index++)); do
      src="${source_root}/${SERVICE_DIRS[$service]}/path-${path_index}"
      [[ -d "${src}" ]] || {
        echo "Incomplete backup: ${service} path ${path_index} is missing; nothing restored." >&2
        return 1
      }
      while IFS= read -r required_file; do
        [[ -s "${src}/${required_file}" ]] || {
          echo "Incomplete backup: ${service} requires populated ${required_file}; nothing restored." >&2
          return 1
        }
      done < <(jq -r --arg service "${service}" --argjson index "${path_index}" '
        if $index == 0 then .[$service].backup.requiredFiles // [] | .[] else empty end
      ' <<<"${registry_json}")
      while IFS= read -r required_directory; do
        [[ -d "${src}/${required_directory}" ]] || {
          echo "Incomplete backup: ${service} requires directory ${required_directory}; nothing restored." >&2
          return 1
        }
      done < <(jq -r --arg service "${service}" --argjson index "${path_index}" '
        if $index == 0 then .[$service].backup.requiredDirectories // [] | .[] else empty end
      ' <<<"${registry_json}")
      if [[ "${path_index}" -eq 0 ]]; then
        validate_service_rdb "${service}" "${src}" || return 1
        validate_service_state_files "${service}" "${src}" || return 1
        validate_service_mongodb_directory "${service}" "${src}" || return 1
      fi
    done
  done
}

restore_from_latest() {
  if [[ ! -d "${LATEST_DIR}" ]]; then
    echo "Missing latest backup directory: ${LATEST_DIR}"
    exit 1
  fi
  validate_restore_source "${LATEST_DIR}"
  DATABASE_DUMP_DIR="${LATEST_DIR}/database-dumps"

  local service
  for service in "${SERVICES[@]}"; do
    stop_service_for_restore "${service}"
  done
  for service in "${SERVICES[@]}"; do
    local configured_paths=()
    local path_index=0
    IFS='|' read -r -a configured_paths <<<"${SERVICE_PATHS[$service]}"
    for _target in "${configured_paths[@]}"; do
      local src="${LATEST_DIR}/${SERVICE_DIRS[$service]}/path-${path_index}"
      if [[ -d "${src}" ]]; then
        restore_service_dir "${service}" "${src}" "${path_index}"
      else
        echo "Incomplete backup: ${service} path ${path_index} is missing." >&2
        exit 1
      fi
      path_index=$((path_index + 1))
    done
  done
}

restore_from_borg() {
  if ! borg list --short "${BORG_REPO}" | grep -Fx -- "${ARCHIVE_NAME}" >/dev/null; then
    echo "Archive not found: ${ARCHIVE_NAME}" >&2
    exit 1
  fi

  TMP_RESTORE_DIR="$(mktemp -d)"

  (
    cd "${TMP_RESTORE_DIR}"
    borg extract --list "${BORG_REPO}::${ARCHIVE_NAME}"
  )
  validate_restore_source "${TMP_RESTORE_DIR}"
  DATABASE_DUMP_DIR="${TMP_RESTORE_DIR}/database-dumps"

  local service
  for service in "${SERVICES[@]}"; do
    stop_service_for_restore "${service}"
  done
  for service in "${SERVICES[@]}"; do
    local directory="${SERVICE_DIRS[$service]}"
    local configured_paths=()
    local path_index=0
    IFS='|' read -r -a configured_paths <<<"${SERVICE_PATHS[$service]}"

    for _target in "${configured_paths[@]}"; do
      local src="${TMP_RESTORE_DIR}/${directory}/path-${path_index}"
      if [[ -n "${src}" && -d "${src}" ]]; then
        restore_service_dir "${service}" "${src}" "${path_index}"
      else
        echo "Incomplete backup: ${service} path ${path_index} is missing." >&2
        exit 1
      fi
      path_index=$((path_index + 1))
    done
  done
}

restore_database_dumps() {
  [[ "${RESTORE_DATABASES}" == true ]] || return 0
  local service
  for service in "${SERVICES[@]}"; do
    restore_service_database "${service}" "${DATABASE_DUMP_DIR}"
  done
}

if [[ "${RESTORE_MODE}" == "latest" ]]; then
  restore_from_latest
else
  restore_from_borg
fi

restore_database_dumps

if [[ "${RESTART_SERVICES}" == true ]]; then
  restart_restored_services
fi
restart_stopped_units

echo "Restore complete."
echo "Symlinked /var/lib service paths are restored to their real targets."
echo "Ownership is reapplied per service for fresh-install compatibility."
if [[ "${RESTART_SERVICES}" == true ]]; then
  echo "Restored services were started or restarted."
else
  echo "Previously running services were restarted; inactive services remain stopped."
  echo "Tip: pass --restart-services to also start restored services that were inactive."
fi
