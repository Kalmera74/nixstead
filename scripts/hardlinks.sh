#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  nixstead media hardlinks compare <reference-directory> <candidate-directory>
  nixstead media hardlinks shared <source-directory> <reference-directory>
  nixstead media hardlinks same-file <search-directory> <file>

Commands:
  compare    Print candidate files not hardlinked to anything in the reference tree
  shared     Print source/reference pairs that share a device and inode
  same-file  Print every file in a tree hardlinked to one selected file
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_directory() {
  [[ -d "$1" ]] || die "directory not found: $1"
}

key_for() {
  stat -c '%d:%i' "$1"
}

operation="${1:-}"
case "${operation}" in
  -h | --help | help)
    usage
    exit 0
    ;;
  compare | shared | same-file) shift ;;
  "")
    usage >&2
    exit 1
    ;;
  *) die "unknown command: ${operation}" ;;
esac

[[ $# -eq 2 ]] || {
  usage >&2
  exit 1
}

for command_name in find stat; do
  command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
done

first="$1"
second="$2"
require_directory "${first}"

if [[ "${operation}" == same-file ]]; then
  [[ -f "${second}" ]] || die "file not found: ${second}"
  find "${first}" -type f -samefile "${second}" -print
  exit
fi

require_directory "${second}"
declare -A reference_files=()

while IFS= read -r -d '' file; do
  reference_files["$(key_for "${file}")"]="${file}"
done < <(find "$([[ "${operation}" == compare ]] && printf '%s' "${first}" || printf '%s' "${second}")" -type f -print0)

scan_root="$([[ "${operation}" == compare ]] && printf '%s' "${second}" || printf '%s' "${first}")"
while IFS= read -r -d '' file; do
  key="$(key_for "${file}")"
  if [[ "${operation}" == compare ]]; then
    [[ -n "${reference_files[${key}]:-}" ]] || printf '%s\n' "${file}"
  elif [[ -n "${reference_files[${key}]:-}" ]]; then
    printf 'Source: %s\nReference: %s\n\n' "${file}" "${reference_files[${key}]}"
  fi
done < <(find "${scan_root}" -type f -print0)
