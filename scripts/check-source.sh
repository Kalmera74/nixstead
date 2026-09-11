#!/usr/bin/env bash
set -euo pipefail

for command_name in bash git ruff shellcheck; do
  command -v "${command_name}" >/dev/null || {
    printf 'Missing command: %s\n' "${command_name}" >&2
    exit 1
  }
done

ruff check setup tests modules/services scripts
while IFS= read -r -d '' script; do
  bash -n "${script}"
  shellcheck --external-sources "${script}"
done < <(git ls-files -z --cached --others --exclude-standard '*.sh')
