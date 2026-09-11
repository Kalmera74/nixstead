#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: nixstead media kavita-import [--apply] <directory>

Organizes loose top-level book files into the one-folder-per-book layout used by
Kavita. Folder names are derived from filenames and sanitized for portability.
The default is a dry run; pass --apply to move files.
EOF
}

APPLY=false
target_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
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
      if [[ -n "${target_dir}" ]]; then
        printf 'Error: only one directory may be supplied.\n' >&2
        usage >&2
        exit 1
      fi
      target_dir="$1"
      shift
      ;;
  esac
done

if [[ -z "${target_dir}" ]]; then
  usage >&2
  exit 1
fi

for command_name in basename mkdir mktemp mv python3 rmdir; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
done

if [[ ! -d "$target_dir" ]]; then
  printf 'Error: directory not found: %s\n' "$target_dir" >&2
  exit 1
fi

sanitize_name() {
  python3 - "$1" <<'PY'
import re
import sys
import unicodedata

name = sys.argv[1]
name = unicodedata.normalize('NFKD', name)
name = ''.join(ch for ch in name if not unicodedata.combining(ch))
name = name.lower()
name = re.sub(r'[^a-z0-9]+', '_', name)
name = re.sub(r'_+', '_', name).strip('_')
print(name or 'item')
PY
}

processed=0
declare -A reserved_destinations=()
pending_tmp=""
pending_original=""
pending_dest=""

restore_pending_move() {
  local exit_code=$?

  if [[ -n "${pending_tmp}" && -e "${pending_tmp}" ]]; then
    if [[ ! -e "${pending_original}" ]]; then
      mv -- "${pending_tmp}" "${pending_original}" ||
        printf 'Recovery required: original remains at %s\n' "${pending_tmp}" >&2
    else
      printf 'Recovery required: original remains at %s\n' "${pending_tmp}" >&2
    fi
  fi

  if [[ -n "${pending_dest}" && -d "${pending_dest}" ]]; then
    rmdir -- "${pending_dest}" 2>/dev/null || true
  fi

  return "${exit_code}"
}
trap restore_pending_move EXIT

for path in "$target_dir"/*; do
  [[ -f "$path" ]] || continue

  filename="$(basename "$path")"
  base_name="${filename%.*}"
  [[ -n "${base_name}" ]] || base_name="${filename}"
  safe_base="$(sanitize_name "${base_name}")"
  dest_dir="$target_dir/$safe_base"

  suffix=2
  while [[ -e "$dest_dir" || -n "${reserved_destinations[${dest_dir}]:-}" ]]; do
    dest_dir="$target_dir/${safe_base}_$suffix"
    suffix=$((suffix + 1))
  done
  reserved_destinations["${dest_dir}"]=1

  if [[ "${APPLY}" != true ]]; then
    printf '[DRY-RUN] %s -> %s/%s\n' "$filename" "$(basename "$dest_dir")" "$filename"
    processed=$((processed + 1))
    continue
  fi

  tmp_path="$(mktemp --tmpdir="${target_dir}" .wrap_tmp.XXXXXX)"
  pending_tmp="${tmp_path}"
  pending_original="${path}"
  pending_dest="${dest_dir}"

  mv -- "$path" "$tmp_path"
  mkdir -- "$dest_dir"
  mv -- "$tmp_path" "$dest_dir/$filename"
  pending_tmp=""
  pending_original=""
  pending_dest=""

  processed=$((processed + 1))
  printf '%s -> %s\n' "$filename" "$(basename "$dest_dir")"
done

if [[ "${APPLY}" == true ]]; then
  printf 'Done. Processed %d file(s).\n' "$processed"
else
  printf 'Dry run complete. %d file(s) would be processed; pass --apply to continue.\n' "$processed"
fi
