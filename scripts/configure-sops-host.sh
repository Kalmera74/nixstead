#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
POLICY_FILE="${REPO_ROOT}/.sops.yaml"
HOST_NAME=""
SSH_PUBLIC_KEY="/etc/ssh/ssh_host_ed25519_key.pub"
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-}"
FORCE=false

usage() {
  cat <<'EOF'
Usage: nixstead --host <name> setup sops [--force] [--ssh-public-key <path>] [--age-key-file <path>]

Creates an admin age identity when needed, derives the host age recipient from
its public SSH Ed25519 key, and adds a host-specific rule to .sops.yaml.

Only public recipients are written to the repository. Private keys remain in
the user's generated-files directory and /etc/ssh on the host.

The admin identity defaults to ~/.local/share/nixstead/sops-age-key.txt.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    --ssh-public-key)
      [[ $# -ge 2 ]] || {
        printf 'Error: --ssh-public-key requires a path.\n' >&2
        exit 1
      }
      SSH_PUBLIC_KEY="$2"
      shift 2
      ;;
    --age-key-file)
      [[ $# -ge 2 ]] || {
        printf 'Error: --age-key-file requires a path.\n' >&2
        exit 1
      }
      AGE_KEY_FILE="$2"
      shift 2
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      [[ -z "${HOST_NAME}" ]] || {
        printf 'Error: only one host may be supplied.\n' >&2
        exit 1
      }
      HOST_NAME="$1"
      shift
      ;;
  esac
done

[[ "${HOST_NAME}" =~ ^[A-Za-z0-9_-]+$ ]] || {
  printf 'Error: host must match [A-Za-z0-9_-]+.\n' >&2
  exit 1
}

default_age_key_file="${HOME}/.local/share/nixstead/sops-age-key.txt"
legacy_age_key_file="${XDG_CONFIG_HOME:-${HOME}/.config}/sops/age/keys.txt"
[[ -n "${AGE_KEY_FILE}" ]] || AGE_KEY_FILE="${default_age_key_file}"

for command_name in age-keygen awk chmod dirname grep mkdir mktemp mv rm ssh-to-age; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

[[ -f "${SSH_PUBLIC_KEY}" ]] || {
  printf 'Error: SSH Ed25519 public key not found: %s\n' "${SSH_PUBLIC_KEY}" >&2
  printf 'Generate host keys first with: sudo ssh-keygen -A\n' >&2
  exit 1
}

mkdir -p "$(dirname "${AGE_KEY_FILE}")"
chmod 0700 "$(dirname "${AGE_KEY_FILE}")"
if [[ "${AGE_KEY_FILE}" == "${default_age_key_file}" && ! -e "${AGE_KEY_FILE}" && -f "${legacy_age_key_file}" ]]; then
  mv -- "${legacy_age_key_file}" "${AGE_KEY_FILE}"
  printf 'Moved the existing admin age identity to %s\n' "${AGE_KEY_FILE}"
fi
if [[ ! -f "${AGE_KEY_FILE}" ]]; then
  age-keygen -o "${AGE_KEY_FILE}"
fi
chmod 0600 "${AGE_KEY_FILE}"

admin_recipient="$(age-keygen -y "${AGE_KEY_FILE}")"
host_recipient="$(ssh-to-age <"${SSH_PUBLIC_KEY}")"
begin_marker="# BEGIN nixstead host: ${HOST_NAME}"
end_marker="# END nixstead host: ${HOST_NAME}"

if [[ -f "${POLICY_FILE}" ]] && grep -Fqx "${begin_marker}" "${POLICY_FILE}"; then
  existing_block="$(awk -v begin="${begin_marker}" -v end="${end_marker}" '
    $0 == begin { printing = 1 }
    printing { print }
    $0 == end { exit }
  ' "${POLICY_FILE}")"

  if [[ "${existing_block}" == *"${admin_recipient}"* && "${existing_block}" == *"${host_recipient}"* ]]; then
    printf 'SOPS policy already has the current recipients for %s.\n' "${HOST_NAME}"
    printf 'Admin identity: %s\n' "${AGE_KEY_FILE}"
    exit 0
  fi

  if [[ "${FORCE}" != true ]]; then
    printf 'Error: SOPS policy has different recipients for %s. Review and rerun with --force.\n' \
      "${HOST_NAME}" >&2
    exit 1
  fi
fi

temporary_policy="$(mktemp "${POLICY_FILE}.XXXXXX")"
trap 'rm -f -- "${temporary_policy}"' EXIT

if [[ -f "${POLICY_FILE}" ]]; then
  awk -v begin="${begin_marker}" -v end="${end_marker}" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "${POLICY_FILE}" >"${temporary_policy}"
else
  printf 'creation_rules:\n' >"${temporary_policy}"
fi

if ! grep -Eq '^creation_rules:[[:space:]]*$' "${temporary_policy}"; then
  printf 'Error: %s does not contain a creation_rules section.\n' "${POLICY_FILE}" >&2
  exit 1
fi

{
  printf '%s\n' "${begin_marker}"
  printf '  - path_regex: secrets/%s\\.yaml$\n' "${HOST_NAME}"
  printf '    key_groups:\n'
  printf '      - age:\n'
  printf '          - %s\n' "${admin_recipient}"
  printf '          - %s\n' "${host_recipient}"
  printf '%s\n' "${end_marker}"
} >>"${temporary_policy}"

mv -- "${temporary_policy}" "${POLICY_FILE}"
trap - EXIT

printf 'Configured SOPS recipients for %s in %s\n' "${HOST_NAME}" "${POLICY_FILE}"
printf 'Admin identity:  %s\n' "${AGE_KEY_FILE}"
printf 'Admin recipient: %s\n' "${admin_recipient}"
printf 'Host recipient:  %s\n' "${host_recipient}"

encrypted_file="${REPO_ROOT}/secrets/${HOST_NAME}.yaml"
if [[ -f "${encrypted_file}" ]]; then
  printf 'Recipients changed for an existing file; run: sops updatekeys --yes %q\n' "${encrypted_file}"
fi
