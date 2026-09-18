#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CONFIGS_DIR="${NIXSTEAD_BACKUP_STATE_DIR:-${REPO_ROOT}/Configs}"
BORG_REPO="${NIXSTEAD_BACKUP_REPOSITORY:-${CONFIGS_DIR}/borg-service-data}"
HOST_NAME="${NIXSTEAD_HOST:-}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
export HOST_NAME SECRETS_DIR
# shellcheck source=scripts/lib/service-databases.sh
# shellcheck disable=SC1091
source "${NIXSTEAD_DATABASE_LIB:-${SCRIPT_DIR}/lib/service-databases.sh}"
ARCHIVE_NAME=""
RESTORE_DIR=""

usage() {
  cat <<'EOF'
Usage: nixstead backup verify [archive-name]

Verifies Borg archive data, extracts an archive into a temporary directory,
and checks declared paths, required files and per-service database recovery
artifacts. Elasticsearch snapshots receive manifest and payload validation;
native RDB files use the selected Redis package's checker. Required files are
relative to the primary archive path; additional archive directories must exist.
It does not import databases or test application recovery. No live path is
modified. The newest archive for NIXSTEAD_HOST is selected by default.
Supply an archive name explicitly to verify a legacy archive without a host prefix.

Environment:
  NIXSTEAD_BACKUP_REPOSITORY  Local or remote Borg repository
  NIXSTEAD_HOST               NixOS configuration name
  NIXSTEAD_SECRETS_DIR        Directory containing the encrypted host file
  BORG_PASSPHRASE/BORG_PASSCOMMAND
EOF
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 1
fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    *) ARCHIVE_NAME="$1" ;;
  esac
fi

# shellcheck source=scripts/lib/nixstead.sh
# shellcheck disable=SC1091
source "${NIXSTEAD_LIB:-${SCRIPT_DIR}/lib/nixstead.sh}"
if [[ -z "${ARCHIVE_NAME}" ]]; then
  ARCHIVE_PREFIX="$(nixstead_backup_archive_prefix)"
fi

for command_name in borg find grep jq mktemp rm tail; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

if [[ -n "${NIXSTEAD_REGISTRY_FILE:-}" ]]; then
  [[ -r "${NIXSTEAD_REGISTRY_FILE}" ]] || {
    printf 'Error: registry metadata is not readable: %s\n' "${NIXSTEAD_REGISTRY_FILE}" >&2
    exit 1
  }
  registry_json="$(<"${NIXSTEAD_REGISTRY_FILE}")"
else
  command -v nix >/dev/null 2>&1 || {
    printf 'Error: required command not found: nix\n' >&2
    exit 1
  }
  registry_json="$(nixstead_config_json nixstead.serviceRegistry)"
fi

if [[ -z "${ARCHIVE_NAME}" ]]; then
  ARCHIVE_NAME="$(borg list --short --glob-archives "${ARCHIVE_PREFIX}*" --last 1 "${BORG_REPO}" | tail -n 1)"
fi
[[ -n "${ARCHIVE_NAME}" ]] || {
  printf 'Error: no service backup for host %s is available in %s; specify an archive name explicitly for legacy backups.\n' "${HOST_NAME}" "${BORG_REPO}" >&2
  exit 1
}

borg check --verify-data --glob-archives "${ARCHIVE_NAME}" "${BORG_REPO}"
RESTORE_DIR="$(mktemp -d)"
trap 'rm -rf -- "${RESTORE_DIR}"' EXIT
(
  cd "${RESTORE_DIR}"
  borg extract "${BORG_REPO}::${ARCHIVE_NAME}"
)

status=0
while IFS=$'\x1f' read -r service directory path_count; do
  [[ -n "${service}" ]] || continue
  validate_database_dump "${service}" "${RESTORE_DIR}" || status=1
  for ((index = 0; index < path_count; index++)); do
    if [[ ! -d "${RESTORE_DIR}/${directory}/path-${index}" ]]; then
      printf '[FAIL] Missing restored path %d for %s (%s).\n' "${index}" "${service}" "${directory}" >&2
      status=1
    fi
    while IFS= read -r required_file; do
      if [[ ! -s "${RESTORE_DIR}/${directory}/path-${index}/${required_file}" ]]; then
        printf '[FAIL] %s requires populated %s.\n' "${service}" "${required_file}" >&2
        status=1
      fi
    done < <(jq -r --arg service "${service}" --argjson index "${index}" '
      if $index == 0 then .[$service].backup.requiredFiles // [] | .[] else empty end
    ' <<<"${registry_json}")
    while IFS= read -r required_directory; do
      if [[ ! -d "${RESTORE_DIR}/${directory}/path-${index}/${required_directory}" ]]; then
        printf '[FAIL] %s requires directory %s.\n' "${service}" "${required_directory}" >&2
        status=1
      fi
    done < <(jq -r --arg service "${service}" --argjson index "${index}" '
      if $index == 0 then .[$service].backup.requiredDirectories // [] | .[] else empty end
    ' <<<"${registry_json}")
    if [[ "${index}" -eq 0 ]]; then
      validate_service_rdb "${service}" "${RESTORE_DIR}/${directory}/path-${index}" || status=1
      validate_service_state_files "${service}" "${RESTORE_DIR}/${directory}/path-${index}" || status=1
      validate_service_mongodb_directory "${service}" "${RESTORE_DIR}/${directory}/path-${index}" || status=1
    fi
  done
done < <(
  jq -r '
    to_entries[]
    | select(.value.enabled and .value.backup != null)
    | [.key, .value.backup.directory, (.value.backup.paths | length)]
    | join("\u001f")
  ' <<<"${registry_json}"
)

if [[ "${status}" -ne 0 ]]; then
  printf 'Restore rehearsal failed for archive %s.\n' "${ARCHIVE_NAME}" >&2
  exit 1
fi

printf 'Archive extraction checks passed for %s; application recovery was not tested.\n' "${ARCHIVE_NAME}"
