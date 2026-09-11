#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
HOST_NAME="${NIXSTEAD_HOST:-}"
COMMAND=""
SELECTOR=""
ORIGINAL_ARGS=("$@")
MANAGED_ARGS=()

# shellcheck source=scripts/lib/nixstead.sh
source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"

usage() {
  cat <<'EOF'
Usage:
  nixstead [global-options] credentials list
  nixstead [global-options] credentials show <service|sops:path/to/key> [--runtime]
  nixstead [global-options] credentials sync [service] [--from <SOPS-path|application>] [--restore] [--dry-run]
  nixstead [global-options] credentials rotate <service> [--dry-run]

Commands:
  list    List retrievable service credentials and every encrypted SOPS key.
          Values are never shown by this command.
  show    Explicitly reveal one service's known credentials, or one exact
          encrypted key selected as sops:path/to/key.

Options:
  --host <name>          NixOS configuration to evaluate.
  --secrets-dir <path>  Directory containing <host>.yaml.
  --repo-root <path>    Nixstead checkout to evaluate.
  --runtime            With show, reveal deployed managed credentials.

Managed show defaults to canonical SOPS values. Sync imports missing keys and
consolidates duplicates; --from resolves a conflict explicitly. --restore marks
a service for restoring its SOPS credential on deployment. Rotate changes the
SOPS credential explicitly. Automatic credential refresh delivers saved changes
and restarts affected consumers; with autoSync disabled, rebuild to deploy them.
--dry-run reports changes without writing.

Examples:
  nixstead --host myhost credentials list
  nixstead --host myhost credentials show nextcloud
  nixstead --host myhost credentials show sops:homepage/piholeApiKey
  sudo nixstead --host <host> credentials show syncthing

Environment:
  NIXSTEAD_HOST         Default host used when --host is omitted.
  NIXSTEAD_SECRETS_DIR  Default secrets directory when --secrets-dir is omitted.

The show command prints plaintext credentials to the terminal. Runtime files
may require sudo. SOPS values require access to a configured age identity.
EOF
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime | --restore | --dry-run)
      MANAGED_ARGS+=("$1")
      shift
      ;;
    --from)
      [[ $# -ge 2 ]] || {
        printf 'Error: --from requires a source.\n' >&2
        exit 1
      }
      MANAGED_ARGS+=("$1" "$2")
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || {
        printf 'Error: --host requires a value.\n' >&2
        exit 1
      }
      HOST_NAME="$2"
      shift 2
      ;;
    --secrets-dir)
      [[ $# -ge 2 ]] || {
        printf 'Error: --secrets-dir requires a value.\n' >&2
        exit 1
      }
      SECRETS_DIR="$2"
      shift 2
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || {
        printf 'Error: --repo-root requires a value.\n' >&2
        exit 1
      }
      REPO_ROOT="$2"
      shift 2
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -z "${COMMAND}" ]]; then
        COMMAND="$1"
      elif [[ -z "${SELECTOR}" ]]; then
        SELECTOR="$1"
      else
        printf 'Error: too many positional arguments.\n' >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ "${COMMAND}" != "list" && "${COMMAND}" != "show" && "${COMMAND}" != "sync" && "${COMMAND}" != "rotate" ]]; then
  [[ -n "${COMMAND}" ]] && printf 'Error: unknown command: %s\n' "${COMMAND}" >&2
  usage
  exit 1
fi

if [[ "${COMMAND}" == "list" && -n "${SELECTOR}" ]]; then
  printf 'Error: list does not accept a selector.\n' >&2
  exit 1
fi

if [[ "${COMMAND}" == "show" && -z "${SELECTOR}" ]]; then
  printf 'Error: show requires a service or SOPS selector.\n' >&2
  usage
  exit 1
fi

nixstead_config_validate_context
require_command nix

if ! command -v jq >/dev/null 2>&1 || ! command -v sops >/dev/null 2>&1; then
  if [[ "${NIXSTEAD_CREDENTIAL_RUNTIME:-}" == "1" ]]; then
    printf 'Error: setup-runtime did not provide both jq and sops.\n' >&2
    exit 1
  fi

  export NIXSTEAD_CREDENTIAL_RUNTIME=1
  exec nix --extra-experimental-features 'nix-command flakes' \
    shell "path:${REPO_ROOT}#setup-runtime" \
    --command "${SCRIPT_PATH}" "${ORIGINAL_ARGS[@]}"
fi

require_command jq
require_command sops

SECRETS_FILE="${SECRETS_DIR}/${HOST_NAME}.yaml"
REGISTRY_JSON="$(nixstead_config_json nixstead.serviceRegistry)"
managed_secrets_file="$(jq -r '[.[] | .credentialSopsFile? // empty] | unique | if length == 1 then .[0] else empty end' <<<"${REGISTRY_JSON}")"
if [[ -n "${managed_secrets_file}" ]]; then
  SECRETS_FILE="${managed_secrets_file}"
fi

managed_credentials() (
  local registry_file
  if ! python3 -c 'import yaml, configobj' >/dev/null 2>&1; then
    [[ "${NIXSTEAD_MANAGED_CREDENTIAL_RUNTIME:-}" != 1 ]] || {
      printf 'Error: missing credential Python dependencies.\n' >&2
      return 1
    }
    export NIXSTEAD_MANAGED_CREDENTIAL_RUNTIME=1
    exec nix --extra-experimental-features 'nix-command flakes' shell "path:${REPO_ROOT}#setup-runtime" --command "${SCRIPT_PATH}" "${ORIGINAL_ARGS[@]}"
  fi
  registry_file="$(mktemp)"
  chmod 600 "${registry_file}"
  trap 'rm -f -- "${registry_file}"' EXIT
  printf '%s\n' "${REGISTRY_JSON}" >"${registry_file}"
  python3 "${NIXSTEAD_CREDENTIAL_STORE:-${REPO_ROOT}/modules/services/arr/credential_store.py}" \
    --registry "${registry_file}" --file "${SECRETS_FILE}" "${MANAGED_ARGS[@]}" "${COMMAND}" "${SELECTOR:-all}"
)

if [[ "${COMMAND}" == sync || "${COMMAND}" == rotate ]] ||
  { [[ "${COMMAND}" == show && "${SELECTOR}" != sops:* ]] && jq -e --arg id "${SELECTOR}" '.[$id].api != null or $id == "qbittorrent"' <<<"${REGISTRY_JSON}" >/dev/null; }; then
  managed_credentials
  exit $?
fi
if [[ ${#MANAGED_ARGS[@]} -gt 0 ]]; then
  printf 'Error: these options require a managed credential operation.\n' >&2
  exit 1
fi

service_sources() {
  local service_name="$1"

  jq -ce --arg service "${service_name}" '
    .[$service] as $entry
    | if $entry == null then error("unknown service: " + $service) else $entry end
    | (
        [(.credentials[]?)]
        + [
            ((.homepage.widget.secrets? // {}) | to_entries[]) as $secret
            | {
                label: ("Homepage " + $secret.key),
                source: {
                  kind: "sops",
                  path: ["homepage", $secret.value]
                }
              }
          ]
      )
    | unique_by([.label, .source.kind, (.source.path // [])])
  ' <<<"${REGISTRY_JSON}"
}

sops_expression() {
  local path_json="$1"

  jq -rn --argjson path "${path_json}" \
    '$path | map("[" + (tojson) + "]") | join("")'
}

show_sops_path() {
  local label="$1"
  local path_json="$2"
  local expression=""
  local value=""

  if ! command -v sops >/dev/null 2>&1; then
    printf '%s: unavailable (sops is not installed; use nix shell path:.#setup-runtime)\n' "${label}"
    return 1
  fi

  if [[ ! -f "${SECRETS_FILE}" ]]; then
    printf '%s: unavailable (encrypted file not found: %s)\n' "${label}" "${SECRETS_FILE}"
    return 1
  fi

  expression="$(sops_expression "${path_json}")"
  if ! value="$(sops decrypt --output-type binary --extract "${expression}" "${SECRETS_FILE}")"; then
    printf '%s: unavailable (could not decrypt %s)\n' "${label}" "${expression}" >&2
    return 1
  fi

  printf '%s: %s\n' "${label}" "${value}"
}

read_runtime_file() {
  local file_path="$1"

  if [[ -r "${file_path}" ]]; then
    command cat -- "${file_path}"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo cat -- "${file_path}"
    return
  fi

  printf 'Error: cannot read runtime credential file: %s\n' "${file_path}" >&2
  return 1
}

show_file_source() {
  local service_name="$1"
  local source_json="$2"
  local label="$3"
  local configured_path=""
  local fallback_path=""
  local fallback_path_option_json="null"
  local suffix=""
  local file_path=""
  local path_option_json="null"
  local env_key=""
  local optional="false"
  local contents=""
  local line=""
  local found=false

  path_option_json="$(jq -c '.pathOption' <<<"${source_json}")"
  if [[ "${path_option_json}" != "null" ]]; then
    configured_path="$(
      jq -r \
        --arg service "${service_name}" \
        --argjson path "${path_option_json}" \
        '.[$service].settings | getpath($path) // empty' \
        <<<"${REGISTRY_JSON}"
    )"
  fi

  fallback_path="$(jq -r '.path // empty' <<<"${source_json}")"
  fallback_path_option_json="$(jq -c '.fallbackPathOption // null' <<<"${source_json}")"
  if [[ -z "${configured_path}" && "${fallback_path_option_json}" != "null" ]]; then
    fallback_path="$(
      jq -r \
        --arg service "${service_name}" \
        --argjson path "${fallback_path_option_json}" \
        '.[$service].settings | getpath($path) // empty' \
        <<<"${REGISTRY_JSON}"
    )"
  fi
  suffix="$(jq -r '.suffix // ""' <<<"${source_json}")"
  if [[ -n "${configured_path}" ]]; then
    file_path="${configured_path}"
  else
    file_path="${fallback_path}${suffix}"
  fi
  env_key="$(jq -r '.envKey // empty' <<<"${source_json}")"
  optional="$(jq -r '.optional // false' <<<"${source_json}")"

  if [[ -z "${file_path}" ]]; then
    if [[ "${optional}" == true ]]; then
      printf '%s: not preseeded\n' "${label}"
      return
    fi
    printf '%s: unavailable (no credential file is configured)\n' "${label}"
    return 1
  fi

  if ! contents="$(read_runtime_file "${file_path}")"; then
    printf '%s: unavailable (cannot read %s)\n' "${label}" "${file_path}"
    return 1
  fi

  if [[ -z "${env_key}" ]]; then
    printf '%s: %s\n' "${label}" "${contents}"
    return
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "${env_key}="* ]]; then
      printf '%s: %s\n' "${label}" "${line#*=}"
      found=true
      break
    fi
  done <<<"${contents}"

  if [[ "${found}" != true ]]; then
    printf '%s: unavailable (%s is missing from %s)\n' "${label}" "${env_key}" "${file_path}"
    return 1
  fi
}

show_service() {
  local service_name="$1"
  local sources_json=""
  local source_entry=""
  local source_json=""
  local source_kind=""
  local label=""
  local path_json=""
  local option_path_json=""
  local value=""
  local warning=""
  local message=""
  local enabled=""
  local failures=0

  if ! sources_json="$(service_sources "${service_name}" 2>/dev/null)"; then
    printf 'Error: unknown service: %s\n' "${service_name}" >&2
    return 1
  fi

  enabled="$(jq -r --arg service "${service_name}" '.[$service].enabled' <<<"${REGISTRY_JSON}")"
  printf '%s credentials (%s):\n' "${service_name}" "$([[ "${enabled}" == true ]] && printf enabled || printf disabled)"

  if [[ "$(jq 'length' <<<"${sources_json}")" -eq 0 ]]; then
    printf '  No credential source is registered for this service.\n'
    return
  fi

  while IFS= read -r source_entry; do
    source_json="$(jq -c '.source' <<<"${source_entry}")"
    source_kind="$(jq -r '.kind' <<<"${source_json}")"
    label="$(jq -r '.label' <<<"${source_entry}")"

    case "${source_kind}" in
      sops)
        path_json="$(jq -c '.path' <<<"${source_json}")"
        show_sops_path "${label}" "${path_json}" || failures=$((failures + 1))
        ;;
      file)
        show_file_source "${service_name}" "${source_json}" "${label}" || failures=$((failures + 1))
        ;;
      option)
        option_path_json="$(jq -c '.path' <<<"${source_json}")"
        value="$(
          jq -r \
            --arg service "${service_name}" \
            --argjson path "${option_path_json}" \
            '.[$service].settings | getpath($path) // empty' \
            <<<"${REGISTRY_JSON}"
        )"
        printf '%s: %s\n' "${label}" "${value:-unavailable}"
        ;;
      literal)
        value="$(jq -r '.value' <<<"${source_json}")"
        warning="$(jq -r '.warning // empty' <<<"${source_json}")"
        printf '%s: %s\n' "${label}" "${value}"
        [[ -z "${warning}" ]] || printf '  Warning: %s\n' "${warning}"
        ;;
      manual)
        message="$(jq -r '.message' <<<"${source_json}")"
        printf 'Setup: %s\n' "${message}"
        ;;
      *)
        printf '%s: unavailable (unsupported source kind: %s)\n' "${label}" "${source_kind}"
        failures=$((failures + 1))
        ;;
    esac
  done < <(jq -c '.[]' <<<"${sources_json}")

  [[ "${failures}" -eq 0 ]]
}

list_credentials() {
  printf 'Credential-aware services:\n'
  jq -r '
    to_entries[]
    | .value as $entry
    | (($entry.credentials // []) | length)
      + (($entry.homepage.widget.secrets? // {}) | length) as $count
    | select($count > 0)
    | "  service:\(.key)\t\(if $entry.enabled then "enabled" else "disabled" end)\t\($count) source(s)"
  ' <<<"${REGISTRY_JSON}"

  if jq -e 'to_entries | any(.[]; .value.enabled and (.value.api != null or .key == "qbittorrent"))' <<<"${REGISTRY_JSON}" >/dev/null; then
    printf '\nManaged credentials (values hidden):\n'
    managed_credentials
  fi

  printf '\nEncrypted SOPS entries (names only):\n'
  if ! command -v sops >/dev/null 2>&1; then
    printf '  unavailable (sops is not installed; use nix shell path:.#setup-runtime)\n'
    return 1
  fi

  if [[ ! -f "${SECRETS_FILE}" ]]; then
    printf '  unavailable (encrypted file not found: %s)\n' "${SECRETS_FILE}"
    return 1
  fi

  if ! sops decrypt --output-type json "${SECRETS_FILE}" |
    jq -r 'paths(scalars) | "  sops:" + (map(tostring) | join("/"))' |
    LC_ALL=C sort; then
    printf 'Error: could not enumerate encrypted entries in %s.\n' "${SECRETS_FILE}" >&2
    return 1
  fi
}

case "${COMMAND}" in
  list)
    list_credentials
    ;;
  show)
    if [[ "${SELECTOR}" == sops:* ]]; then
      sops_selector="${SELECTOR#sops:}"
      if [[ -z "${sops_selector}" || "${sops_selector}" == /* || "${sops_selector}" == */ || "${sops_selector}" == *//* ]]; then
        printf 'Error: invalid SOPS selector: %s\n' "${SELECTOR}" >&2
        exit 1
      fi
      path_json="$(jq -cn --arg path "${sops_selector}" '$path | split("/")')"
      show_sops_path "${SELECTOR}" "${path_json}"
    else
      show_service "${SELECTOR}"
    fi
    ;;
esac
