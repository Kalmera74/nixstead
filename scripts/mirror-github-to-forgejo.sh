#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

INPUT_FILE=""
HOST_NAME="${NIXSTEAD_HOST:-}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
FORGEJO_URL="${FORGEJO_URL:-}"
FORGEJO_TOKEN_FILE="${FORGEJO_TOKEN_FILE:-}"
FORGEJO_TOKEN=""
FORGEJO_OWNER="${FORGEJO_OWNER:-}"
MIRROR_PRIVATE="true"
SYNC_AFTER_IMPORT="true"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage:
  nixstead [--host <name>] forge mirror -i <input-file> [options]

Required:
  -i, --input <path>         Any text/markdown file containing GitHub repo links

Options:
  --host <name>              NixOS host config (required unless NIXSTEAD_HOST is set)
  -u, --forgejo-url <url>    Forgejo base URL (default: nixstead.services.dev.forgejo)
  -t, --token-file <path>    File containing the Forgejo API token
  -o, --owner <owner>        Target owner/user/org (default: token user)
  -p, --private <true|false> Create mirrors as private repos (default: true)
  -s, --sync <true|false>    Trigger mirror pull right after import (default: true)
  -n, --dry-run              Print actions without API calls

Environment:
  FORGEJO_URL
  FORGEJO_TOKEN_FILE
  FORGEJO_OWNER

Examples:
  nixstead forge mirror -i ./github-migrate.md -n
  nixstead forge mirror -i notes.txt -u http://127.0.0.1:3000 -o my-user
EOF
}

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "[FAIL] Missing command: ${command_name}" >&2
    exit 1
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

sanitize_repo_name() {
  local value="$1"
  value="${value//\`/}"
  value="${value//\*/}"
  value="${value// /-}"
  value="${value//\//-}"
  value="${value//:/-}"
  value="${value//[^[:alnum:]_.-]/-}"
  value="$(trim "${value}")"
  value="${value#-}"
  value="${value%-}"
  printf '%s' "${value}"
}

normalize_repo_url() {
  local input_url="$1"
  local without_fragment="${input_url%%#*}"
  local without_query="${without_fragment%%\?*}"
  local cleaned="${without_query%/}"

  if [[ "${cleaned}" =~ ^https?://github\.com/([^/]+)/([^/]+)$ ]]; then
    local gh_owner="${BASH_REMATCH[1]}"
    local gh_repo="${BASH_REMATCH[2]}"
    gh_repo="${gh_repo%.git}"

    if [[ -z "${gh_owner}" || -z "${gh_repo}" ]]; then
      return 1
    fi

    printf 'https://github.com/%s/%s.git' "${gh_owner}" "${gh_repo}"
    return 0
  fi

  return 1
}

extract_repo_name_from_url() {
  local normalized_url="$1"
  local repo_name
  repo_name="$(basename "${normalized_url%.git}")"
  sanitize_repo_name "${repo_name}"
}

extract_github_repo_urls() {
  local file_path="$1"
  local raw_urls

  raw_urls="$(rg -o --no-filename 'https?://github\.com/[^[:space:])>"\]\}]+' "${file_path}" || true)"

  if [[ -z "${raw_urls}" ]]; then
    return 0
  fi

  local line
  while IFS= read -r line; do
    local candidate
    candidate="${line%%\`*}"
    candidate="${candidate%%,*}"
    candidate="${candidate%%;*}"
    candidate="${candidate%%!*}"
    candidate="$(trim "${candidate}")"

    local normalized
    if normalized="$(normalize_repo_url "${candidate}")"; then
      printf '%s\n' "${normalized}"
    else
      echo "[WARN] Skipping non-repo link: ${candidate}" >&2
    fi
  done <<<"${raw_urls}" | sort -u
}

parse_input_links() {
  local file_path="$1"

  while IFS= read -r repo_url; do
    [[ -n "${repo_url}" ]] || continue
    local repo_name
    repo_name="$(extract_repo_name_from_url "${repo_url}")"
    [[ -n "${repo_name}" ]] || repo_name="repo"
    printf '%s\t%s\n' "${repo_name}" "${repo_url}"
  done < <(extract_github_repo_urls "${file_path}")
}

api_request() {
  local method="$1"
  local endpoint="$2"
  local payload="$3"

  local response
  response="$(
    printf 'header = "Authorization: token %s"\n' "${FORGEJO_TOKEN}" |
      curl --config - -sS -w '\n%{http_code}' \
        -X "${method}" \
        -H 'Content-Type: application/json' \
        --data "${payload}" \
        "${FORGEJO_URL}${endpoint}"
  )"

  local status_code
  status_code="$(printf '%s\n' "${response}" | tail -n1)"
  local body
  body="$(printf '%s\n' "${response}" | sed '$d')"

  printf '%s\n%s' "${status_code}" "${body}"
}

get_owner_from_token() {
  local response
  response="$(
    printf 'header = "Authorization: token %s"\n' "${FORGEJO_TOKEN}" |
      curl --config - -sS -w '\n%{http_code}' "${FORGEJO_URL}/api/v1/user"
  )"

  local status_code
  status_code="$(printf '%s\n' "${response}" | tail -n1)"
  local body
  body="$(printf '%s\n' "${response}" | sed '$d')"

  if [[ "${status_code}" != "200" ]]; then
    echo "[FAIL] Unable to resolve token user (HTTP ${status_code})" >&2
    echo "${body}" >&2
    exit 1
  fi

  jq -r '.login // empty' <<<"${body}"
}

import_mirror() {
  local repo_name="$1"
  local clone_url="$2"

  local payload
  payload="$(jq -cn \
    --arg clone_addr "${clone_url}" \
    --arg repo_name "${repo_name}" \
    --arg repo_owner "${FORGEJO_OWNER}" \
    --argjson private "${MIRROR_PRIVATE}" \
    '{clone_addr:$clone_addr, repo_name:$repo_name, repo_owner:$repo_owner, mirror:true, private:$private, service:"git"}')"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY] import ${FORGEJO_OWNER}/${repo_name} <= ${clone_url}"
    return 0
  fi

  local status_and_body
  status_and_body="$(api_request POST '/api/v1/repos/migrate' "${payload}")"

  local status_code
  status_code="$(printf '%s\n' "${status_and_body}" | head -n1)"
  local body
  body="$(printf '%s\n' "${status_and_body}" | tail -n +2)"

  if [[ "${status_code}" == "201" ]]; then
    echo "[ OK ] Imported ${FORGEJO_OWNER}/${repo_name}"
    return 0
  fi

  if [[ "${status_code}" == "409" ]]; then
    echo "[WARN] Already exists: ${FORGEJO_OWNER}/${repo_name}"
    return 2
  fi

  echo "[FAIL] Import failed for ${FORGEJO_OWNER}/${repo_name} (HTTP ${status_code})" >&2
  echo "${body}" >&2
  return 1
}

sync_mirror() {
  local repo_name="$1"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY] sync ${FORGEJO_OWNER}/${repo_name}"
    return 0
  fi

  local status_and_body
  status_and_body="$(api_request POST "/api/v1/repos/${FORGEJO_OWNER}/${repo_name}/mirror-sync" '{}')"

  local status_code
  status_code="$(printf '%s\n' "${status_and_body}" | head -n1)"
  local body
  body="$(printf '%s\n' "${status_and_body}" | tail -n +2)"

  if [[ "${status_code}" == "200" || "${status_code}" == "202" || "${status_code}" == "204" ]]; then
    echo "[ OK ] Synced ${FORGEJO_OWNER}/${repo_name}"
    return 0
  fi

  echo "[WARN] Sync failed for ${FORGEJO_OWNER}/${repo_name} (HTTP ${status_code})" >&2
  echo "${body}" >&2
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i | --input)
      [[ $# -ge 2 ]] || {
        echo "[FAIL] $1 requires a value" >&2
        exit 1
      }
      INPUT_FILE="${2:-}"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || {
        echo "[FAIL] --host requires a value" >&2
        exit 1
      }
      HOST_NAME="${2:-}"
      shift 2
      ;;
    -u | --forgejo-url)
      [[ $# -ge 2 ]] || {
        echo "[FAIL] $1 requires a value" >&2
        exit 1
      }
      FORGEJO_URL="${2:-}"
      shift 2
      ;;
    -t | --token-file)
      [[ $# -ge 2 ]] || {
        echo "[FAIL] $1 requires a value" >&2
        exit 1
      }
      FORGEJO_TOKEN_FILE="${2:-}"
      shift 2
      ;;
    -o | --owner)
      [[ $# -ge 2 ]] || {
        echo "[FAIL] $1 requires a value" >&2
        exit 1
      }
      FORGEJO_OWNER="${2:-}"
      shift 2
      ;;
    -p | --private)
      [[ $# -ge 2 ]] || {
        echo "[FAIL] $1 requires a value" >&2
        exit 1
      }
      MIRROR_PRIVATE="${2:-}"
      shift 2
      ;;
    -s | --sync)
      [[ $# -ge 2 ]] || {
        echo "[FAIL] $1 requires a value" >&2
        exit 1
      }
      SYNC_AFTER_IMPORT="${2:-}"
      shift 2
      ;;
    -n | --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${INPUT_FILE}" ]]; then
  echo "[FAIL] --input/-i is required" >&2
  usage
  exit 1
fi

if [[ ! -f "${INPUT_FILE}" ]]; then
  echo "[FAIL] Input file not found: ${INPUT_FILE}" >&2
  exit 1
fi

if [[ "${MIRROR_PRIVATE}" != "true" && "${MIRROR_PRIVATE}" != "false" ]]; then
  echo "[FAIL] --private must be true or false" >&2
  exit 1
fi

if [[ "${SYNC_AFTER_IMPORT}" != "true" && "${SYNC_AFTER_IMPORT}" != "false" ]]; then
  echo "[FAIL] --sync must be true or false" >&2
  exit 1
fi

require_cmd curl
require_cmd jq
require_cmd rg

if [[ -z "${FORGEJO_URL}" ]]; then
  require_cmd nix
  # shellcheck source=scripts/lib/nixstead.sh
  source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"

  forgejo_ip="$(nixstead_config_raw nixstead.services.dev.forgejo.ip)"
  forgejo_port="$(nixstead_config_raw nixstead.services.dev.forgejo.port)"
  if [[ -z "${forgejo_ip}" || -z "${forgejo_port}" ]]; then
    echo "[FAIL] Could not resolve nixstead.services.dev.forgejo.ip/port" >&2
    exit 1
  fi
  FORGEJO_URL="http://${forgejo_ip}:${forgejo_port}"
fi

FORGEJO_URL="${FORGEJO_URL%/}"

if [[ "${DRY_RUN}" != "true" ]]; then
  [[ -n "${FORGEJO_TOKEN_FILE}" ]] || {
    echo "[FAIL] Missing Forgejo token file. Set --token-file or FORGEJO_TOKEN_FILE." >&2
    exit 1
  }
  [[ -r "${FORGEJO_TOKEN_FILE}" ]] || {
    echo "[FAIL] Forgejo token file is not readable: ${FORGEJO_TOKEN_FILE}" >&2
    exit 1
  }
  IFS= read -r FORGEJO_TOKEN <"${FORGEJO_TOKEN_FILE}" || true
  [[ -n "${FORGEJO_TOKEN}" ]] || {
    echo "[FAIL] Forgejo token file is empty: ${FORGEJO_TOKEN_FILE}" >&2
    exit 1
  }
  [[ "${FORGEJO_TOKEN}" != *[$'\r\n"\\']* ]] || {
    echo "[FAIL] Forgejo token contains characters that cannot be passed safely." >&2
    exit 1
  }
fi

if [[ -z "${FORGEJO_OWNER}" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    FORGEJO_OWNER="<owner>"
  else
    FORGEJO_OWNER="$(get_owner_from_token)"
  fi
fi

echo "==> Input file: ${INPUT_FILE}"
echo "==> Forgejo URL: ${FORGEJO_URL}"
echo "==> Target owner: ${FORGEJO_OWNER}"
echo "==> Private mirrors: ${MIRROR_PRIVATE}"
echo "==> Sync after import: ${SYNC_AFTER_IMPORT}"
echo "==> Dry run: ${DRY_RUN}"

imported_count=0
existing_count=0
failed_count=0
synced_count=0

while IFS=$'\t' read -r repo_name repo_url; do
  [[ -n "${repo_name}" && -n "${repo_url}" ]] || continue

  if import_mirror "${repo_name}" "${repo_url}"; then
    imported_count=$((imported_count + 1))
    if [[ "${SYNC_AFTER_IMPORT}" == "true" ]]; then
      if sync_mirror "${repo_name}"; then
        synced_count=$((synced_count + 1))
      fi
    fi
  else
    exit_code=$?
    if [[ "${exit_code}" -eq 2 ]]; then
      existing_count=$((existing_count + 1))
      if [[ "${SYNC_AFTER_IMPORT}" == "true" ]]; then
        if sync_mirror "${repo_name}"; then
          synced_count=$((synced_count + 1))
        fi
      fi
    else
      failed_count=$((failed_count + 1))
    fi
  fi
done < <(parse_input_links "${INPUT_FILE}")

echo "==> Done"
echo "Imported: ${imported_count}"
echo "Already existed: ${existing_count}"
echo "Synced: ${synced_count}"
echo "Failed: ${failed_count}"

if [[ "${failed_count}" -gt 0 ]]; then
  exit 1
fi
