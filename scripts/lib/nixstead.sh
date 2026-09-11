#!/usr/bin/env bash

# Shared NixOS configuration lookup helpers.
# Callers must set REPO_ROOT and HOST_NAME before invoking these functions.

nixstead_require_host() {
  if [[ -z "${HOST_NAME:-}" ]]; then
    printf '%s\n' "Error: select a NixOS configuration with NIXSTEAD_HOST or the command's host argument. Host-installed commands supply this default." >&2
    return 1
  fi

  if [[ ! "${HOST_NAME:-}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf 'Error: invalid NixOS configuration name: %s\n' "${HOST_NAME:-<unset>}" >&2
    return 1
  fi
}

nixstead_config_validate_context() {
  nixstead_require_host || return 1
  if [[ -z "${REPO_ROOT:-}" || ! -f "${REPO_ROOT}/flake.nix" ]]; then
    printf 'Error: REPO_ROOT does not point to a Nix flake: %s\n' "${REPO_ROOT:-<unset>}" >&2
    return 1
  fi
}

nixstead_config_ref() {
  local option_path="$1"

  nixstead_config_validate_context || return 1
  if [[ ! "${option_path}" =~ ^[A-Za-z0-9_.\"]+$ ]]; then
    printf 'Error: invalid Nix option path: %s\n' "${option_path}" >&2
    return 1
  fi

  printf 'path:%s#nixosConfigurations."%s".config.%s' \
    "${REPO_ROOT}" "${HOST_NAME}" "${option_path}"
}

nixstead_config_json() {
  local option_path="$1"
  local reference
  reference="$(nixstead_config_ref "${option_path}")" || return 1

  NIXSTEAD_SECRETS_DIR="${SECRETS_DIR:-${REPO_ROOT}/secrets}" \
    nix --extra-experimental-features 'nix-command flakes' \
    eval --json --impure "${reference}"
}

nixstead_config_raw() {
  local option_path="$1"
  local reference
  reference="$(nixstead_config_ref "${option_path}")" || return 1

  NIXSTEAD_SECRETS_DIR="${SECRETS_DIR:-${REPO_ROOT}/secrets}" \
    nix --extra-experimental-features 'nix-command flakes' \
    eval --raw --impure \
    --apply 'value: if value == null then "" else if builtins.isBool value then (if value then "true" else "false") else builtins.toString value' \
    "${reference}"
}

nixstead_config_apply_raw() {
  local option_path="$1"
  local apply_expression="$2"
  local reference
  reference="$(nixstead_config_ref "${option_path}")" || return 1

  NIXSTEAD_SECRETS_DIR="${SECRETS_DIR:-${REPO_ROOT}/secrets}" \
    nix --extra-experimental-features 'nix-command flakes' \
    eval --raw --impure --apply "${apply_expression}" "${reference}"
}

nixstead_config_attr_names_json() {
  local option_path="$1"
  local reference
  reference="$(nixstead_config_ref "${option_path}")" || return 1

  NIXSTEAD_SECRETS_DIR="${SECRETS_DIR:-${REPO_ROOT}/secrets}" \
    nix --extra-experimental-features 'nix-command flakes' \
    eval --json --impure --apply builtins.attrNames "${reference}"
}

nixstead_config_enabled() {
  [[ "$(nixstead_config_raw "$1" 2>/dev/null || true)" == "true" ]]
}
