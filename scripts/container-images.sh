#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"

usage() {
  cat <<'EOF'
Usage:
  nixstead [--host <name>] images list
  nixstead [--host <name>] images set [--dry-run] [--allow-downgrade] <service> <component> <tag-or-reference> [...]
  nixstead [--host <name>] images reset [--dry-run] [--allow-downgrade] <service> <component> [...]
  nixstead [--host <name>] images diff

Manage host-specific, digest-pinned OCI image overrides.

The set command accepts one or more SERVICE COMPONENT IMAGE triplets. IMAGE may
be a tag such as 5.2.1 or the component's complete repository:tag reference,
with or without a digest. Tags are resolved and verified with skopeo before the
override file is changed.

The reset command accepts one or more SERVICE COMPONENT pairs. It removes only
overrides managed in hosts/<host>/container-images.nix.

Mutating commands validate the resulting flake and roll back the file if the
check fails. They never rebuild or activate NixOS.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_runtime() {
  local action="$1"
  local -a required=(jq)
  local -a missing=()
  local command_name

  [[ "${action}" == "set" ]] && required+=(skopeo)
  [[ "${action}" == "diff" ]] && required+=(git)

  command -v nix >/dev/null 2>&1 || die "nix is required"
  for command_name in "${required[@]}"; do
    command -v "${command_name}" >/dev/null 2>&1 || missing+=("${command_name}")
  done

  if ((${#missing[@]} == 0)); then
    return
  fi

  if [[ "${NIXSTEAD_CONTAINER_IMAGES_BOOTSTRAPPED:-0}" == "1" ]]; then
    die "missing required commands after entering the runtime environment: ${missing[*]}"
  fi

  printf 'Loading container image tools with nix shell: %s\n' "${missing[*]}" >&2
  NIXSTEAD_CONTAINER_IMAGES_BOOTSTRAPPED=1 exec nix \
    --extra-experimental-features 'nix-command flakes' \
    shell "path:${REPO_ROOT}#container-image-runtime" \
    --command "$0" "$@"
}

validate_host() {
  local host="$1"

  [[ "${host}" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid host name: ${host}"
  [[ -f "${REPO_ROOT}/flake.nix" ]] || die "repository root is not a flake: ${REPO_ROOT}"
}

load_inventory() {
  local expression
  expression='let
    flake = builtins.getFlake ("path:" + builtins.getEnv "NIXSTEAD_REPOSITORY");
    system = builtins.getAttr (builtins.getEnv "NIXSTEAD_HOST") flake.nixosConfigurations;
    registry = system.config.nixstead.serviceRegistry;
    getPath = path: value:
      if path == []
      then value
      else getPath (builtins.tail path) (builtins.getAttr (builtins.head path) value);
  in
    builtins.mapAttrs (
      serviceId: entry: {
        inherit (entry) name optionPath;
        stateful = entry.backup != null;
        components = builtins.mapAttrs (
          component: metadata:
            metadata // {
              default = metadata.default;
              effective = getPath (["nixstead" "services"] ++ entry.optionPath ++ ["images" component]) system.config;
            }
        ) entry.ociImages;
      }
    ) registry'

  NIXSTEAD_REPOSITORY="${REPO_ROOT}" \
    NIXSTEAD_HOST="${HOST_NAME}" \
    NIXSTEAD_SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}" \
    nix --extra-experimental-features 'nix-command flakes' \
    eval --json --impure --expr "${expression}" |
    jq 'with_entries(select((.value.components | length) > 0))'
}

load_overrides() {
  if [[ -f "${OVERRIDE_FILE}" ]]; then
    nix --extra-experimental-features 'nix-command flakes' \
      eval --json --file "${OVERRIDE_FILE}"
  else
    printf '{}\n'
  fi
}

validate_component() {
  local service="$1"
  local component="$2"

  jq -e --arg service "${service}" '.[$service]' <<<"${INVENTORY_JSON}" >/dev/null ||
    die "service '${service}' has no registry-managed OCI images"
  jq -e --arg service "${service}" --arg component "${component}" \
    '.[$service].components[$component]' <<<"${INVENTORY_JSON}" >/dev/null ||
    die "service '${service}' has no image component '${component}'"
}

component_value() {
  local service="$1"
  local component="$2"
  local field="$3"

  jq -r --arg service "${service}" --arg component "${component}" --arg field "${field}" \
    '.[$service].components[$component][$field]' <<<"${INVENTORY_JSON}"
}

image_tag() {
  local repository="$1"
  local reference="$2"
  local remainder

  [[ "${reference}" == "${repository}:"*"@sha256:"* ]] || return 1
  remainder="${reference#"${repository}:"}"
  printf '%s\n' "${remainder%@sha256:*}"
}

version_key() {
  local tag="${1#v}"

  if [[ "${tag}" =~ ^([0-9]+([.][0-9]+)*)([-+._].*)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  return 1
}

is_downgrade() {
  local current_tag="$1"
  local requested_tag="$2"
  local current_version requested_version first

  current_version="$(version_key "${current_tag}")" || return 1
  requested_version="$(version_key "${requested_tag}")" || return 1
  [[ "${current_version}" != "${requested_version}" ]] || return 1
  first="$(printf '%s\n%s\n' "${requested_version}" "${current_version}" | sort -V | head -n 1)"
  [[ "${first}" == "${requested_version}" ]]
}

check_downgrade() {
  local service="$1"
  local component="$2"
  local current="$3"
  local requested="$4"
  local repository current_tag requested_tag stateful role

  repository="$(component_value "${service}" "${component}" repository)"
  current_tag="$(image_tag "${repository}" "${current}")" || return
  requested_tag="$(image_tag "${repository}" "${requested}")" || return

  if ! version_key "${current_tag}" >/dev/null || ! version_key "${requested_tag}" >/dev/null; then
    printf 'Warning: could not determine whether %s.%s changes %s to %s as a downgrade; review it manually.\n' \
      "${service}" "${component}" "${current_tag}" "${requested_tag}" >&2
    return
  fi

  if is_downgrade "${current_tag}" "${requested_tag}"; then
    stateful="$(jq -r --arg service "${service}" '.[$service].stateful' <<<"${INVENTORY_JSON}")"
    role="$(component_value "${service}" "${component}" role)"
    if [[ "${ALLOW_DOWNGRADE}" != "true" ]]; then
      die "${service}.${component} would downgrade ${current_tag} to ${requested_tag}; rerun with --allow-downgrade after reviewing migrations and backups"
    fi
    printf 'Warning: allowing downgrade of %s.%s (%s) from %s to %s' \
      "${service}" "${component}" "${role}" "${current_tag}" "${requested_tag}" >&2
    [[ "${stateful}" == "true" ]] && printf ' on a stateful service' >&2
    printf '.\n' >&2
  fi
}

resolve_image() {
  local service="$1"
  local component="$2"
  local requested="$3"
  local repository tag supplied_digest resolved_digest reference

  repository="$(component_value "${service}" "${component}" repository)"

  if [[ "${requested}" == "${repository}:"* ]]; then
    reference="${requested}"
    if [[ "${reference}" == *"@"* ]]; then
      supplied_digest="${reference##*@}"
      reference="${reference%@*}"
    else
      supplied_digest=""
    fi
    tag="${reference#"${repository}:"}"
  elif [[ "${requested}" == *"/"* || "${requested}" == *":"* || "${requested}" == *"@"* ]]; then
    die "${service}.${component} must use repository ${repository}"
  else
    tag="${requested}"
    supplied_digest=""
  fi

  [[ "${tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] ||
    die "invalid image tag for ${service}.${component}: ${tag}"
  [[ "${tag}" != "latest" ]] || die "floating 'latest' tags are not allowed"
  if [[ -n "${supplied_digest}" && ! "${supplied_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    die "invalid digest for ${service}.${component}: ${supplied_digest}"
  fi

  printf 'Resolving %s:%s...\n' "${repository}" "${tag}" >&2
  resolved_digest="$(skopeo inspect --format '{{.Digest}}' "docker://${repository}:${tag}")" ||
    die "could not resolve ${repository}:${tag}"
  [[ "${resolved_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] ||
    die "registry returned an invalid digest for ${repository}:${tag}"
  if [[ -n "${supplied_digest}" && "${supplied_digest}" != "${resolved_digest}" ]]; then
    die "supplied digest for ${repository}:${tag} does not match the registry (${resolved_digest})"
  fi

  printf '%s:%s@%s\n' "${repository}" "${tag}" "${resolved_digest}"
}

render_overrides() {
  local json="$1"
  local output="$2"
  local service component image quoted_image

  printf '{\n' >"${output}"
  while IFS= read -r service; do
    printf '  "%s" = {\n' "${service}" >>"${output}"
    while IFS= read -r component; do
      image="$(jq -r --arg service "${service}" --arg component "${component}" \
        '.[$service][$component]' <<<"${json}")"
      quoted_image="$(jq -n --arg image "${image}" '$image')"
      printf '    "%s" = %s;\n' "${component}" "${quoted_image}" >>"${output}"
    done < <(jq -r --arg service "${service}" '.[$service] | keys[]' <<<"${json}")
    printf '  };\n' >>"${output}"
  done < <(jq -r 'keys[]' <<<"${json}")
  printf '}\n' >>"${output}"
}

validate_override_json() {
  local json="$1"
  local service component image repository

  while IFS=$'\t' read -r service component image; do
    validate_component "${service}" "${component}"
    [[ "${image}" =~ ^[^[:space:]@]+:[A-Za-z0-9_][A-Za-z0-9_.-]*@sha256:[0-9a-f]{64}$ ]] ||
      die "invalid pinned image in generated overrides: ${service}.${component}"
    repository="$(component_value "${service}" "${component}" repository)"
    [[ "${image}" == "${repository}:"* ]] ||
      die "generated override ${service}.${component} must use repository ${repository}"
  done < <(jq -r 'to_entries[] | .key as $service | .value | to_entries[] | [$service, .key, .value] | @tsv' <<<"${json}")
}

apply_changes() {
  local new_json="$1"
  local operation="$2"
  local rendered backup="" had_original=false

  validate_override_json "${new_json}"
  rendered="$(mktemp "${HOST_DIR}/.container-images.nix.XXXXXX")"
  render_overrides "${new_json}" "${rendered}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '\nDry run: %s would produce:\n' "${operation}"
    cat "${rendered}"
    rm -f -- "${rendered}"
    return
  fi

  if [[ -f "${OVERRIDE_FILE}" ]]; then
    had_original=true
    backup="$(mktemp "${HOST_DIR}/.container-images.backup.XXXXXX")"
    cp -- "${OVERRIDE_FILE}" "${backup}"
  fi

  mv -- "${rendered}" "${OVERRIDE_FILE}"

  printf 'Validating the updated configuration with nix flake check...\n' >&2
  if ! NIXSTEAD_SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}" \
    nix --extra-experimental-features 'nix-command flakes' flake check "path:${REPO_ROOT}"; then
    if [[ "${had_original}" == "true" ]]; then
      mv -- "${backup}" "${OVERRIDE_FILE}"
    else
      rm -f -- "${OVERRIDE_FILE}"
    fi
    die "flake validation failed; restored the previous override file"
  fi

  [[ -z "${backup}" ]] || rm -f -- "${backup}"
  printf '%s complete: %s\n' "${operation}" "${OVERRIDE_FILE}"
  printf 'No system was rebuilt or activated. Review the diff before switching.\n'
}

list_images() {
  local service component role stateful repository default effective managed

  while IFS=$'\t' read -r service component; do
    role="$(component_value "${service}" "${component}" role)"
    stateful="$(jq -r --arg service "${service}" '.[$service].stateful' <<<"${INVENTORY_JSON}")"
    repository="$(component_value "${service}" "${component}" repository)"
    default="$(component_value "${service}" "${component}" default)"
    effective="$(component_value "${service}" "${component}" effective)"
    managed="$(jq -r --arg service "${service}" --arg component "${component}" \
      '.[$service][$component] // ""' <<<"${OVERRIDES_JSON}")"
    printf '%s.%s  role=%s  stateful=%s\n' "${service}" "${component}" "${role}" "${stateful}"
    printf '  repository: %s\n' "${repository}"
    printf '  default:    %s\n' "${default}"
    printf '  effective:  %s\n' "${effective}"
    if [[ -n "${managed}" ]]; then
      printf '  managed:    %s\n' "${managed}"
    else
      printf '  managed:    <none>\n'
    fi
  done < <(jq -r 'to_entries[] | .key as $service | .value.components | keys[] | [$service, .] | @tsv' <<<"${INVENTORY_JSON}")
}

show_diff() {
  if [[ ! -f "${OVERRIDE_FILE}" ]]; then
    printf 'No generated container image overrides for %s.\n' "${HOST_NAME}"
    return
  fi

  if git -C "${REPO_ROOT}" ls-files --error-unmatch -- "${OVERRIDE_FILE#"${REPO_ROOT}/"}" >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" diff -- "${OVERRIDE_FILE#"${REPO_ROOT}/"}"
  else
    git -C "${REPO_ROOT}" diff --no-index -- /dev/null "${OVERRIDE_FILE}" || true
  fi
}

if (($# == 0)); then
  usage
  exit 1
fi

ACTION="$1"
shift
case "${ACTION}" in
  list | set | reset | diff) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown action: ${ACTION}"
    ;;
esac

require_runtime "${ACTION}" "$@"

DRY_RUN=false
ALLOW_DOWNGRADE=false
if [[ "${ACTION}" == "set" || "${ACTION}" == "reset" ]]; then
  while (($# > 0)); do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --allow-downgrade) ALLOW_DOWNGRADE=true ;;
      --)
        shift
        break
        ;;
      -*) die "unknown option: $1" ;;
      *) break ;;
    esac
    shift
  done
fi

(($# > 0)) || die "a host name is required"
HOST_NAME="$1"
shift
validate_host "${HOST_NAME}"
if [[ -n "${NIXSTEAD_HOST_DIRECTORY:-}" ]]; then
  HOST_DIR="${NIXSTEAD_HOST_DIRECTORY}"
elif [[ -f "${REPO_ROOT}/hosts/${HOST_NAME}/default.nix" ]]; then
  HOST_DIR="${REPO_ROOT}/hosts/${HOST_NAME}"
else
  HOST_DIR="${REPO_ROOT}"
fi
if [[ ! -f "${HOST_DIR}/default.nix" && ! -f "${HOST_DIR}/configuration.nix" ]]; then
  die "could not locate the mutable module for ${HOST_NAME}; set NIXSTEAD_HOST_DIRECTORY"
fi
OVERRIDE_FILE="${HOST_DIR}/container-images.nix"

if [[ "${ACTION}" == "diff" ]]; then
  (($# == 0)) || die "diff accepts only a host name"
  show_diff
  exit
fi

INVENTORY_JSON="$(load_inventory)"
OVERRIDES_JSON="$(load_overrides)"

if [[ "${ACTION}" == "list" ]]; then
  (($# == 0)) || die "list accepts only a host name"
  list_images
  exit
fi

if [[ "${ACTION}" == "set" ]]; then
  (($# > 0 && $# % 3 == 0)) || die "set requires one or more SERVICE COMPONENT IMAGE triplets"
  NEW_OVERRIDES_JSON="${OVERRIDES_JSON}"
  while (($# > 0)); do
    service="$1"
    component="$2"
    requested="$3"
    shift 3
    validate_component "${service}" "${component}"
    resolved="$(resolve_image "${service}" "${component}" "${requested}")"
    current="$(component_value "${service}" "${component}" effective)"
    check_downgrade "${service}" "${component}" "${current}" "${resolved}"
    NEW_OVERRIDES_JSON="$(jq --arg service "${service}" --arg component "${component}" --arg image "${resolved}" \
      '.[$service][$component] = $image' <<<"${NEW_OVERRIDES_JSON}")"
  done
  apply_changes "${NEW_OVERRIDES_JSON}" "Container image update"
  exit
fi

(($# > 0 && $# % 2 == 0)) || die "reset requires one or more SERVICE COMPONENT pairs"
NEW_OVERRIDES_JSON="${OVERRIDES_JSON}"
while (($# > 0)); do
  service="$1"
  component="$2"
  shift 2
  validate_component "${service}" "${component}"
  managed="$(jq -r --arg service "${service}" --arg component "${component}" \
    '.[$service][$component] // ""' <<<"${NEW_OVERRIDES_JSON}")"
  [[ -n "${managed}" ]] || die "${service}.${component} has no generated override to reset"
  current="$(component_value "${service}" "${component}" effective)"
  default="$(component_value "${service}" "${component}" default)"
  if [[ "${current}" == "${managed}" ]]; then
    check_downgrade "${service}" "${component}" "${current}" "${default}"
  fi
  NEW_OVERRIDES_JSON="$(jq --arg service "${service}" --arg component "${component}" '
    del(.[$service][$component])
    | if ((.[$service] // {}) | length) == 0 then del(.[$service]) else . end
  ' <<<"${NEW_OVERRIDES_JSON}")"
done
apply_changes "${NEW_OVERRIDES_JSON}" "Container image reset"
