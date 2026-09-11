#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
HOST_NAME="${NIXSTEAD_HOST:-}"
SECRETS_DIR_SET=false
STRICT_LOCAL=false

usage() {
  cat <<'EOF'
Usage:
  nixstead [--host <name>] [--secrets-dir <path>] check secrets homepage
  nixstead [--host <name>] [--secrets-dir <path>] credentials validate homepage

Compares the Homepage keys in the encrypted <host>.yaml file with the tracked
plaintext schema in secrets/secrets.example.yaml. Secret values are never
printed or written to temporary files.

Options:
  --host <name>    Configuration/host name (required unless NIXSTEAD_HOST is set)
  --strict-local   Fail if the encrypted host file is missing
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || {
        printf 'Error: --host requires a value.\n' >&2
        exit 1
      }
      HOST_NAME="$2"
      shift 2
      ;;
    --strict-local)
      STRICT_LOCAL=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ "${SECRETS_DIR_SET}" == true ]]; then
        printf 'Error: only one secrets directory may be supplied.\n' >&2
        exit 1
      fi
      SECRETS_DIR="$1"
      SECRETS_DIR_SET=true
      shift
      ;;
  esac
done

# shellcheck source=scripts/lib/nixstead.sh
source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
nixstead_require_host

for command_name in awk comm jq mktemp rm sed sops sort; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

example_file="${NIXSTEAD_SECRET_SCHEMA:-${REPO_ROOT}/secrets/secrets.example.yaml}"
encrypted_file="${SECRETS_DIR}/${HOST_NAME}.yaml"

[[ -f "${example_file}" ]] || {
  printf '[FAIL] Missing schema: %s\n' "${example_file}" >&2
  exit 1
}

if [[ ! -f "${encrypted_file}" ]]; then
  if [[ "${STRICT_LOCAL}" == true ]]; then
    printf '[FAIL] Encrypted host file missing: %s\n' "${encrypted_file}" >&2
    exit 1
  fi
  printf '[WARN] Encrypted host file missing (skipped): %s\n' "${encrypted_file}"
  exit 0
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "${temporary_directory}"' EXIT
expected_keys="${temporary_directory}/expected"
actual_keys="${temporary_directory}/actual"
missing_keys="${temporary_directory}/missing"
extra_keys="${temporary_directory}/extra"

awk '
  /^homepage:[[:space:]]*$/ { in_homepage = 1; next }
  in_homepage && /^[^[:space:]]/ { exit }
  in_homepage && /^  [A-Za-z_][A-Za-z0-9_]*:/ {
    key = $1
    sub(/:$/, "", key)
    print key
  }
' "${example_file}" | sort -u >"${expected_keys}"

sops decrypt --output-type json "${encrypted_file}" |
  jq -r '.homepage | keys[]' |
  sort -u >"${actual_keys}"

comm -23 "${expected_keys}" "${actual_keys}" >"${missing_keys}"
comm -13 "${expected_keys}" "${actual_keys}" >"${extra_keys}"

status=0
if [[ -s "${missing_keys}" ]]; then
  printf '[FAIL] Missing Homepage keys:\n'
  sed 's/^/  - /' "${missing_keys}"
  status=1
else
  printf '[ OK ] No missing Homepage keys.\n'
fi

if [[ -s "${extra_keys}" ]]; then
  printf '[WARN] Extra Homepage keys:\n'
  sed 's/^/  - /' "${extra_keys}"
else
  printf '[ OK ] No extra Homepage keys.\n'
fi

if [[ "${status}" -ne 0 ]]; then
  printf '==> Homepage secret key consistency check failed.\n'
  exit 1
fi

printf '==> Homepage secret key consistency check passed.\n'
