#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CONFIGS_DIR="${NIXSTEAD_BACKUP_STATE_DIR:-${REPO_ROOT}/Configs}"
BORG_REPO="${NIXSTEAD_BACKUP_REPOSITORY:-${CONFIGS_DIR}/borg-service-data}"
LATEST_DIR="${CONFIGS_DIR}/service-configs-latest"
BACKUP_SCOPE="${NIXSTEAD_BACKUP_SCOPE:-full}"
VERIFY_BACKUP="${NIXSTEAD_BACKUP_VERIFY:-true}"
KEEP_LAST="${NIXSTEAD_BACKUP_KEEP_LAST:-}"
STAGING_DIR=""
HOST_NAME="${NIXSTEAD_HOST:-}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
export HOST_NAME SECRETS_DIR
# shellcheck source=scripts/lib/service-databases.sh
# shellcheck disable=SC1091
source "${NIXSTEAD_DATABASE_LIB:-${SCRIPT_DIR}/lib/service-databases.sh}"

usage() {
  cat <<'EOF'
Usage: sudo --preserve-env=BORG_PASSPHRASE,BORG_PASSCOMMAND nixstead backup create

Creates an encrypted Borg archive and refreshes the latest recovery copy
for services with a backup policy in the central service registry.
Services that are running are paused while the consistent snapshot is staged.

Set BORG_PASSPHRASE or BORG_PASSCOMMAND before creating or opening the Borg
repository. New repositories use repokey-blake2 encryption.
Set NIXSTEAD_HOST to select a configuration when using the repository script.
Set NIXSTEAD_BACKUP_REPOSITORY to a local or remote Borg repository.
Set NIXSTEAD_BACKUP_INIT=true once when initializing a remote repository.
Set NIXSTEAD_BACKUP_SCOPE=config to retain the former config-only exclusions;
the default full scope includes application data and database files.
Set NIXSTEAD_BACKUP_VERIFY=false to skip post-create data verification.
Set NIXSTEAD_BACKUP_KEEP_LAST to a positive archive count to replace the
default 7 daily, 4 weekly and 6 monthly retention policy.
EOF
}

if [[ $# -gt 0 ]]; then
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  fi
  echo "Error: this script does not accept arguments." >&2
  usage >&2
  exit 1
fi

PRUNE_ARGS=(--keep-daily 7 --keep-weekly 4 --keep-monthly 6)
RETENTION_DESCRIPTION="7 daily, 4 weekly, and 6 monthly archives"
if [[ -n "${KEEP_LAST}" ]]; then
  [[ "${KEEP_LAST}" =~ ^[1-9][0-9]*$ ]] || {
    echo "NIXSTEAD_BACKUP_KEEP_LAST must be a positive integer." >&2
    exit 1
  }
  PRUNE_ARGS=(--keep-last "${KEEP_LAST}")
  RETENTION_DESCRIPTION="last ${KEEP_LAST} archives"
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo) so service state can be read consistently." >&2
  exit 1
fi

# Compatibility exclusions for the optional config-only scope.
SYNC_EXCLUDES=(
  --exclude='logs/'
  --exclude='Logs/'
  --exclude='log/'
  --exclude='*.log'
  --exclude='cache/'
  --exclude='.cache/'
  --exclude='metadata/'
  --exclude='data/'
  --exclude='MediaCover/'
  --exclude='Sentry/'
  --exclude='asp/'
  --exclude='backup/'
  --exclude='restore/'
  --exclude='downloads/'
)

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

for command_name in borg chmod chown date grep id jq mkdir mktemp readlink rm rsync runuser stat systemctl; do
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
declare -A SERVICE_UNITS=()
declare -A SERVICE_DATABASES=()

while IFS=$'\x1f' read -r service directory path units database; do
  [[ -n "${service}" ]] || continue
  SERVICES+=("${service}")
  SERVICE_DIRS["${service}"]="${directory}"
  SERVICE_PATHS["${service}"]="${path}"
  SERVICE_UNITS["${service}"]="${units}"
  SERVICE_DATABASES["${service}"]="${database}"
done < <(
  jq -r '
    to_entries[]
    | select(.value.enabled and .value.backup != null)
    | [.key, .value.backup.directory, (.value.backup.paths | join("|")), (.value.backup.units | join(",")), (.value.backup.database // "")]
    | join("\u001f")
  ' <<<"${registry_json}"
)

declare -A SOURCE_PATHS=()
SOURCE_PATH_COUNT=0
STAGED_SERVICES=()
STOPPED_UNITS=()

restart_stopped_services() {
  local failed=false
  local remaining_units=()
  local unit
  local index
  for ((index = ${#STOPPED_UNITS[@]} - 1; index >= 0; index--)); do
    unit="${STOPPED_UNITS[$index]}"
    if systemctl start "${unit}"; then
      echo "Restarted ${unit}."
    else
      echo "Failed to restart ${unit}." >&2
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

  if ! restart_stopped_services; then
    echo "Warning: one or more services could not be restarted." >&2
    exit_code=1
  fi

  if [[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]]; then
    rm -rf -- "${STAGING_DIR}"
  fi

  exit "${exit_code}"
}
trap cleanup EXIT

mkdir -p "${CONFIGS_DIR}"

if repository_info="$(borg info --json "${BORG_REPO}" 2>/dev/null)"; then
  if grep -Eq '"mode"[[:space:]]*:[[:space:]]*"none"' <<<"${repository_info}"; then
    echo "Refusing to use unencrypted Borg repository: ${BORG_REPO}" >&2
    echo "Preserve it separately, then initialize a new encrypted repository at this path." >&2
    exit 1
  fi
else
  if [[ "${BORG_REPO}" == *:* && "${NIXSTEAD_BACKUP_INIT:-false}" != "true" ]]; then
    echo "Remote Borg repository is unavailable or uninitialized: ${BORG_REPO}" >&2
    echo "Set NIXSTEAD_BACKUP_INIT=true only when intentionally initializing it." >&2
    exit 1
  fi
  echo "Initializing encrypted Borg repository: ${BORG_REPO}"
  borg init --encryption=repokey-blake2 "${BORG_REPO}"
fi

for service in "${SERVICES[@]}"; do
  resolved_paths=()
  IFS='|' read -r -a service_paths <<<"${SERVICE_PATHS[$service]}"
  for service_dir in "${service_paths[@]}"; do
    resolved_dir="$(readlink -f "${service_dir}" 2>/dev/null || true)"
    if [[ -n "${resolved_dir}" && -d "${resolved_dir}" ]]; then
      resolved_paths+=("${resolved_dir}")
      SOURCE_PATH_COUNT=$((SOURCE_PATH_COUNT + 1))
    else
      echo "Incomplete backup: required state path is missing for ${service}: ${service_dir}" >&2
      exit 1
    fi
  done
  SOURCE_PATHS["${service}"]="$(
    IFS='|'
    echo "${resolved_paths[*]}"
  )"
done

if [[ "${SOURCE_PATH_COUNT}" -eq 0 ]]; then
  echo "No enabled service backup paths were found." >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d)"

# Validate every engine before stopping any service.
DATABASE_UNITS=()
for service in "${SERVICES[@]}"; do
  validate_database_policy "${service}"
  case "${SERVICE_DATABASES[$service]:-}" in
    postgresql)
      require_cmd pg_dump
      require_cmd pg_dumpall
      if [[ "$(database_field "${service}" databaseFormat)" == custom ]]; then
        require_cmd pg_restore
      fi
      id postgres >/dev/null
      ;;
    mariadb-container | postgresql-container) require_cmd docker ;;
    elasticsearch-container)
      require_cmd docker
      require_cmd python3
      ;;
  esac
  database_unit="$(database_field "${service}" databaseUnit)"
  if [[ -n "${database_unit}" ]]; then
    systemctl is-active --quiet "${database_unit}" || {
      echo "Database must be running to dump ${service}: ${database_unit}" >&2
      exit 1
    }
    DATABASE_UNITS+=("${database_unit}")
  fi
done

for service in "${SERVICES[@]}"; do
  if [[ -z "${SOURCE_PATHS[$service]:-}" ]]; then
    continue
  fi

  IFS=',' read -r -a units <<<"${SERVICE_UNITS[$service]:-}"
  for unit in "${units[@]}"; do
    if [[ " ${DATABASE_UNITS[*]} " == *" ${unit} "* ]]; then
      continue
    fi
    if [[ -n "${unit}" ]] && systemctl is-active --quiet "${unit}"; then
      systemctl stop "${unit}"
      STOPPED_UNITS+=("${unit}")
      echo "Stopped ${unit} for a consistent snapshot."
    fi
  done
done

# Writers are stopped, but database servers remain available for logical dumps.
mkdir -p "${STAGING_DIR}/database-dumps"
for service in "${SERVICES[@]}"; do
  dump_service_database "${service}" "$(database_dump_path "${service}" "${STAGING_DIR}/database-dumps")"
  validate_database_dump "${service}" "${STAGING_DIR}"
done
# Stop companion databases only after their dump, before copying physical files.
for unit in "${DATABASE_UNITS[@]}"; do
  # Only databases declared as snapshot units need a physical stop. A scoped
  # logical backup must not interrupt unrelated users of shared PostgreSQL.
  if ! jq -e --arg unit "${unit}" 'to_entries | any(.value.enabled and .value.backup != null and (.value.backup.units | index($unit) != null))' <<<"${registry_json}" >/dev/null; then
    continue
  fi
  if systemctl is-active --quiet "${unit}"; then
    systemctl stop "${unit}"
    STOPPED_UNITS+=("${unit}")
  fi
done

for service in "${SERVICES[@]}"; do
  sources="${SOURCE_PATHS[$service]:-}"
  if [[ -z "${sources}" ]]; then
    continue
  fi

  archive_dir="${SERVICE_DIRS[$service]}"
  IFS='|' read -r -a source_paths <<<"${sources}"
  path_index=0
  for source in "${source_paths[@]}"; do
    destination="${STAGING_DIR}/${archive_dir}/path-${path_index}"
    mkdir -p "${destination}"
    if [[ "${BACKUP_SCOPE}" == "config" ]]; then
      rsync -a "${SYNC_EXCLUDES[@]}" "${source}/" "${destination}/"
    elif [[ "${BACKUP_SCOPE}" == "full" ]]; then
      rsync -a "${source}/" "${destination}/"
    else
      echo "Invalid NIXSTEAD_BACKUP_SCOPE: ${BACKUP_SCOPE} (expected full or config)" >&2
      exit 1
    fi
    while IFS= read -r required_file; do
      [[ -s "${destination}/${required_file}" ]] || {
        echo "Incomplete backup: ${service} requires populated ${required_file}. Use full scope for application state." >&2
        exit 1
      }
    done < <(jq -r --arg service "${service}" --argjson index "${path_index}" '
      if $index == 0 then .[$service].backup.requiredFiles // [] | .[] else empty end
    ' <<<"${registry_json}")
    while IFS= read -r required_directory; do
      [[ -d "${destination}/${required_directory}" ]] || {
        echo "Incomplete backup: ${service} requires directory ${required_directory}. Use full scope for application state." >&2
        exit 1
      }
    done < <(jq -r --arg service "${service}" --argjson index "${path_index}" '
      if $index == 0 then .[$service].backup.requiredDirectories // [] | .[] else empty end
    ' <<<"${registry_json}")
    if [[ "${path_index}" -eq 0 ]]; then
      validate_service_rdb "${service}" "${destination}"
      validate_service_state_files "${service}" "${destination}"
      validate_service_mongodb_directory "${service}" "${destination}"
    fi
    path_index=$((path_index + 1))
  done
  STAGED_SERVICES+=("${archive_dir}")
done

# The live services do not need to remain stopped while Borg processes the snapshot.
restart_stopped_services

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
(
  cd "${STAGING_DIR}"
  borg create \
    --stats \
    --compression lz4 \
    "${BORG_REPO}::service-data-${TIMESTAMP}" \
    "${STAGED_SERVICES[@]}" database-dumps
)

if [[ "${VERIFY_BACKUP}" == "true" ]]; then
  borg check --verify-data --glob-archives "service-data-${TIMESTAMP}" "${BORG_REPO}"
elif [[ "${VERIFY_BACKUP}" != "false" ]]; then
  echo "Invalid NIXSTEAD_BACKUP_VERIFY: ${VERIFY_BACKUP} (expected true or false)" >&2
  exit 1
fi

borg prune \
  --list \
  --glob-archives 'service-data-*' \
  "${PRUNE_ARGS[@]}" \
  "${BORG_REPO}"
borg compact "${BORG_REPO}"

if [[ "${LATEST_DIR}" != "${CONFIGS_DIR}/service-configs-latest" ]]; then
  echo "Refusing to refresh unexpected latest-backup path: ${LATEST_DIR}" >&2
  exit 1
fi
mkdir -p "${LATEST_DIR}"
rsync -a --delete "${STAGING_DIR}/" "${LATEST_DIR}/"

OWNER_USER="${SUDO_USER:-}"
if [[ -z "${OWNER_USER}" ]]; then
  OWNER_USER="$(stat -c '%U' "${CONFIGS_DIR}")"
fi
OWNER_GROUP="$(id -gn "${OWNER_USER}")"

if [[ -n "${OWNER_USER}" && "${OWNER_USER}" != "root" ]]; then
  chown -R "${OWNER_USER}:${OWNER_GROUP}" "${CONFIGS_DIR}"
fi

echo "Backup complete."
echo "Borg repo: ${BORG_REPO}"
echo "Latest copy: ${LATEST_DIR}"
echo "Retention: ${RETENTION_DESCRIPTION}."
echo "Scope: ${BACKUP_SCOPE}."
echo "Services and companion database containers were paused while state was staged."
echo "Verification: ${VERIFY_BACKUP}."
