#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
HOST_NAME="${NIXSTEAD_HOST:-}"

usage() {
  cat <<'EOF'
Usage: nixstead [--host <name>] credentials configure homepage

Prompts for post-install API keys and login credentials used by enabled
unmanaged Homepage widgets and writes the encrypted Homepage branch. Supported
ARR and Seerr credentials are enrolled and delivered automatically when shared
credentials are enabled. Deploy unmanaged widget changes with the normal rebuild.

qBittorrent uses the plaintext credential stored in its bootstrap branch. To
rotate it, use nixstead credentials rotate qbittorrent. Automatic refresh
delivers saved changes; rebuild only when autoSync is disabled.

Options:
  --host <name>  Configuration name (required unless NIXSTEAD_HOST is set)
  -h, --help     Show this help
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
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# shellcheck source=scripts/lib/nixstead.sh
source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
nixstead_config_validate_context

for command_name in nix sops; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

encrypted_file="${SECRETS_DIR}/${HOST_NAME}.yaml"
[[ -f "${encrypted_file}" ]] || {
  printf 'Error: encrypted host file not found: %s\n' "${encrypted_file}" >&2
  exit 1
}

if ! nixstead_config_enabled nixstead.services.homepage.enable; then
  printf 'Error: Homepage is not enabled for %s.\n' "${HOST_NAME}" >&2
  exit 1
fi

NIXSTEAD_HOST="${HOST_NAME}" NIXSTEAD_SECRETS_DIR="${SECRETS_DIR}" \
  "${NIXSTEAD_GENERATE_CREDENTIALS_SCRIPT:-${REPO_ROOT}/scripts/generate-credential-files.sh}" --force homepage

if nixstead_config_enabled nixstead.services.arr.swaparr.enable &&
  nixstead_config_enabled nixstead.services.arr.readarr.enable; then
  NIXSTEAD_HOST="${HOST_NAME}" NIXSTEAD_SECRETS_DIR="${SECRETS_DIR}" \
    "${NIXSTEAD_GENERATE_CREDENTIALS_SCRIPT:-${REPO_ROOT}/scripts/generate-credential-files.sh}" --force swaparr
fi

printf 'Homepage integration credentials updated for %s.\n' "${HOST_NAME}"
printf 'Rebuild to deploy unmanaged widgets. Managed media credentials are enrolled and refreshed automatically.\n'
