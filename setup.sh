#!/usr/bin/env bash
set -euo pipefail

# Source launcher for first-time setup before the grouped CLI is installed.
# The implementation lives in the readable Python package under setup/.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v nix >/dev/null 2>&1; then
  # nix shell supplies Python and the packaged setup application only for this
  # invocation. The shell is discarded as soon as nixstead-setup exits.
  NIXSTEAD_REPO_ROOT="${REPO_ROOT}" \
    NIXSTEAD_FRAMEWORK_ROOT="${REPO_ROOT}" \
    exec nix shell \
    --extra-experimental-features 'nix-command flakes' \
    "path:${REPO_ROOT}#setup" \
    --command nixstead-setup "$@"
fi

printf '%s\n' 'Error: Nix is required to run the setup wizard.' >&2
exit 1
