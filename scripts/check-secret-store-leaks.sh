#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOST_NAME="${1:-${NIXSTEAD_HOST:-}}"
SECRETS_DIR="${2:-${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}}"
SECRETS_FILE="${SECRETS_DIR}/${HOST_NAME}.yaml"

usage() {
  cat <<'EOF'
Usage: nixstead [--host <name>] [--secrets-dir <path>] check secrets store

Decrypts sensitive scalar values into a mode-0700 temporary directory, then
checks the evaluated system derivation and small/config-like paths in its Nix
store closure. Matching content is never printed; only a leaking store path is
reported. The temporary pattern file is removed on exit.
EOF
}

if [[ "${HOST_NAME}" == "-h" || "${HOST_NAME}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

# shellcheck source=scripts/lib/nixstead.sh
source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
nixstead_config_validate_context

for command_name in basename jq mktemp nix nix-store rg rm sops sort stat; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

[[ -f "${SECRETS_FILE}" ]] || {
  printf 'Error: encrypted host file not found: %s\n' "${SECRETS_FILE}" >&2
  exit 1
}

temporary_directory="$(mktemp -d)"
chmod 0700 "${temporary_directory}"
trap 'rm -rf -- "${temporary_directory}"' EXIT
patterns_file="${temporary_directory}/patterns"
derivation_json="${temporary_directory}/derivation.json"

sops decrypt --output-type json "${SECRETS_FILE}" |
  jq -r '
      paths(scalars) as $path
      | select(($path[-1] | tostring | test("password|secret|token|api.?key|masterkey"; "i")))
      | getpath($path)
      | strings
      # Very short/common values create false positives in package metadata.
      # Production credentials should be longer than this minimum anyway.
      | select(length >= 12)
    ' |
  sort -u >"${patterns_file}"

if [[ ! -s "${patterns_file}" ]]; then
  printf 'No non-empty sensitive scalar values were found; nothing to scan.\n'
  exit 0
fi

system_derivation="$(nixstead_config_raw system.build.toplevel.drvPath)"
nix --extra-experimental-features 'nix-command flakes' \
  derivation show "${system_derivation}" >"${derivation_json}"

if rg --quiet --fixed-strings --file "${patterns_file}" "${derivation_json}"; then
  printf '[FAIL] Plaintext secret found in system derivation metadata: %s\n' "${system_derivation}" >&2
  exit 1
fi

status=0
while IFS= read -r store_path; do
  [[ -e "${store_path}" ]] || continue

  if [[ -f "${store_path}" ]]; then
    size="$(stat -c '%s' "${store_path}" 2>/dev/null || printf '0')"
    [[ "${size}" -le 4194304 ]] || continue
  elif [[ -d "${store_path}" ]]; then
    case "$(basename "${store_path}")" in
      *config* | *environment* | *etc* | *script* | *secret* | *sops* | *system-units* | *unit*) ;;
      *) continue ;;
    esac
  else
    continue
  fi

  if rg --quiet --fixed-strings --file "${patterns_file}" --max-filesize 4M "${store_path}" 2>/dev/null; then
    printf '[FAIL] Plaintext secret found in referenced store path: %s\n' "${store_path}" >&2
    status=1
  fi
done < <(nix-store --query --requisites "${system_derivation}")

if [[ "${status}" -ne 0 ]]; then
  exit 1
fi

printf '[ OK ] No encrypted host secret value was found in the evaluated Nix store closure.\n'
