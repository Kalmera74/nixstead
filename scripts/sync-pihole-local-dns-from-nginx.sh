#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixstead [--host <name>] dns sync [options]

Syncs Pi-hole Local DNS records from enabled DNS participants in the resolved
service registry.

Options:
  --host <name>            NixOS host config name (required unless NIXSTEAD_HOST is set)
  --repo-root <path>       Nixstead repo root (default: auto)
  --secrets-dir <path>     Secrets directory (default: NIXSTEAD_SECRETS_DIR or <repo>/secrets)
  --registry-file <path>   Pre-evaluated nixstead.serviceRegistry JSON
  --host-file <path>       Pre-evaluated nixstead.host JSON
  --pihole-url <url>       Pi-hole base URL (default: nixstead.services.pihole.ip/port)
  --credential-file <path> Read the Pi-hole credential from a runtime file
  --state-file <path>      Track exact domains owned by this sync process
  --prune-managed          Remove managed domains that no longer exist in desired set
  --skip-missing-credential
                           Exit successfully when the credential is empty or a placeholder
  --apply                  Perform changes (default: dry-run)
  --help                   Show this help

Examples:
  nixstead dns sync
  nixstead dns sync --apply
  nixstead dns sync --credential-file /run/secrets/pihole --apply --prune-managed
EOF
}

require_cmd() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
}

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOST_NAME="${NIXSTEAD_HOST:-}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
SECRETS_DIR_EXPLICIT=false
REGISTRY_FILE=""
HOST_FILE=""
PIHOLE_URL=""
PIHOLE_CREDENTIAL=""
CREDENTIAL_FILE="${NIXSTEAD_PIHOLE_CREDENTIAL_FILE:-}"
if [[ -z "${CREDENTIAL_FILE}" && -n "${CREDENTIALS_DIRECTORY:-}" ]]; then
  CREDENTIAL_FILE="${CREDENTIALS_DIRECTORY}/pihole-password"
fi
STATE_FILE=""
APPLY=false
PRUNE_MANAGED=false
SKIP_MISSING_CREDENTIAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || {
        printf 'Error: --host requires a value\n' >&2
        exit 1
      }
      HOST_NAME="${2:-}"
      shift 2
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || {
        printf 'Error: --repo-root requires a value\n' >&2
        exit 1
      }
      REPO_ROOT="${2:-}"
      if [[ "${SECRETS_DIR_EXPLICIT}" == false ]]; then
        SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
      fi
      shift 2
      ;;
    --secrets-dir)
      [[ $# -ge 2 ]] || {
        printf 'Error: --secrets-dir requires a value\n' >&2
        exit 1
      }
      SECRETS_DIR="${2:-}"
      SECRETS_DIR_EXPLICIT=true
      shift 2
      ;;
    --registry-file)
      [[ $# -ge 2 ]] || {
        printf 'Error: --registry-file requires a value\n' >&2
        exit 1
      }
      REGISTRY_FILE="${2:-}"
      shift 2
      ;;
    --host-file)
      [[ $# -ge 2 ]] || {
        printf 'Error: --host-file requires a value\n' >&2
        exit 1
      }
      HOST_FILE="${2:-}"
      shift 2
      ;;
    --pihole-url)
      [[ $# -ge 2 ]] || {
        printf 'Error: --pihole-url requires a value\n' >&2
        exit 1
      }
      PIHOLE_URL="${2:-}"
      shift 2
      ;;
    --credential-file)
      [[ $# -ge 2 ]] || {
        printf 'Error: --credential-file requires a value\n' >&2
        exit 1
      }
      CREDENTIAL_FILE="${2:-}"
      shift 2
      ;;
    --state-file)
      [[ $# -ge 2 ]] || {
        printf 'Error: --state-file requires a value\n' >&2
        exit 1
      }
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --prune-managed)
      PRUNE_MANAGED=true
      shift
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    --skip-missing-credential)
      SKIP_MISSING_CREDENTIAL=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd jq
require_cmd curl
require_cmd awk
require_cmd cut
require_cmd sort

if [[ -n "${REGISTRY_FILE}" ]]; then
  [[ -r "${REGISTRY_FILE}" ]] || {
    printf 'Error: registry JSON is not readable: %s\n' "${REGISTRY_FILE}" >&2
    exit 1
  }
  registry_json="$(<"${REGISTRY_FILE}")"
else
  require_cmd nix
  # shellcheck source=scripts/lib/nixstead.sh
  # shellcheck disable=SC1091
  source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
  registry_json="$(nixstead_config_json nixstead.serviceRegistry)"
fi

if [[ -n "${HOST_FILE}" ]]; then
  [[ -r "${HOST_FILE}" ]] || {
    printf 'Error: host JSON is not readable: %s\n' "${HOST_FILE}" >&2
    exit 1
  }
  host_json="$(<"${HOST_FILE}")"
else
  if ! declare -F nixstead_config_json >/dev/null 2>&1; then
    require_cmd nix
    # shellcheck source=scripts/lib/nixstead.sh
    # shellcheck disable=SC1091
    source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
  fi
  host_json="$(nixstead_config_json nixstead.host)"
fi

if ! printf '%s' "${registry_json}" | jq -e 'type == "object"' >/dev/null ||
  ! printf '%s' "${host_json}" | jq -e 'type == "object"' >/dev/null; then
  printf 'Error: registry and host inputs must contain JSON objects\n' >&2
  exit 1
fi

nginx_ip="$(printf '%s' "${host_json}" | jq -r '.network.lan // empty')"

if [[ -z "${nginx_ip}" ]]; then
  printf 'Error: nixstead.host.network.lan is required as the Nginx DNS target\n' >&2
  exit 1
fi

if [[ -z "${PIHOLE_URL}" ]]; then
  pihole_ip="$(printf '%s' "${registry_json}" | jq -r '.pihole.settings.ip // empty')"
  pihole_port="$(printf '%s' "${registry_json}" | jq -r '.pihole.settings.port // empty')"
  if [[ -z "${pihole_ip}" ]]; then
    printf 'Error: nixstead.services.pihole.ip is missing\n' >&2
    exit 1
  fi
  PIHOLE_URL="http://${pihole_ip}${pihole_port:+:${pihole_port}}"
fi

if [[ -z "${PIHOLE_CREDENTIAL}" && -n "${CREDENTIAL_FILE}" ]]; then
  if [[ ! -r "${CREDENTIAL_FILE}" ]]; then
    printf 'Error: Pi-hole credential file is not readable: %s\n' "${CREDENTIAL_FILE}" >&2
    exit 1
  fi
  PIHOLE_CREDENTIAL="$(<"${CREDENTIAL_FILE}")"
fi

if [[ -z "${PIHOLE_CREDENTIAL}" && -n "${HOST_NAME}" ]]; then
  # shellcheck source=scripts/lib/nixstead.sh
  # shellcheck disable=SC1091
  source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"
  nixstead_require_host
fi
if [[ -z "${PIHOLE_CREDENTIAL}" && -n "${HOST_NAME}" && -f "${SECRETS_DIR}/${HOST_NAME}.yaml" ]]; then
  require_cmd sops
  PIHOLE_CREDENTIAL="$(sops decrypt --extract '["homepage"]["piholeApiKey"]' "${SECRETS_DIR}/${HOST_NAME}.yaml" 2>/dev/null || true)"
fi

if [[ -z "${PIHOLE_CREDENTIAL}" || "${PIHOLE_CREDENTIAL}" == "replace-me" ]]; then
  if [[ "${SKIP_MISSING_CREDENTIAL}" == true ]]; then
    printf 'Pi-hole credential is empty or still a placeholder; skipping DNS synchronization.\n'
    exit 0
  fi
  printf 'Error: missing Pi-hole credential (--credential-file or encrypted host secrets)\n' >&2
  exit 1
fi

candidate_records_json="$(
  printf '%s' "${registry_json}" | jq -c --arg nginxIp "${nginx_ip}" '
    [
      to_entries[]
      | select(.value.enabled and .value.dns and .value.settings.domain != null)
      | { domain: .value.settings.domain, ip: $nginxIp }
    ]
    | unique_by([.domain, .ip])
  '
)"
current_managed_domains_json="$(
  printf '%s' "${candidate_records_json}" | jq -c 'map(.domain) | unique | sort'
)"
previous_managed_domains_json='[]'
state_managed=false

if [[ -n "${STATE_FILE}" ]]; then
  state_managed=true
  if [[ -e "${STATE_FILE}" ]]; then
    if [[ ! -r "${STATE_FILE}" ]]; then
      printf 'Error: managed-domain state is not readable: %s\n' "${STATE_FILE}" >&2
      exit 1
    fi
    if ! jq -e 'type == "array" and all(.[]; type == "string")' "${STATE_FILE}" >/dev/null; then
      printf 'Error: managed-domain state must be a JSON array of domain names: %s\n' "${STATE_FILE}" >&2
      exit 1
    fi
    previous_managed_domains_json="$(jq -c 'unique | sort' "${STATE_FILE}")"
  fi
fi

conflict_domains_json="$(
  jq -cn \
    --argjson current "${current_managed_domains_json}" \
    --argjson previous "${previous_managed_domains_json}" \
    --argjson prune "${PRUNE_MANAGED}" \
    --argjson stateManaged "${state_managed}" \
    '$current + (if $prune and $stateManaged then $previous else [] end) | unique'
)"

record_conflicts="$(
  printf '%s' "${candidate_records_json}" | jq -r '
    group_by(.domain)[]
    | select((map(.ip) | unique | length) > 1)
    | "\(.[0].domain): \(map(.ip) | unique | join(", "))"
  '
)"

if [[ -n "${record_conflicts}" ]]; then
  printf 'Error: conflicting service IPs were found for the same domain:\n%s\n' "${record_conflicts}" >&2
  exit 1
fi

desired_records="$(
  printf '%s' "${candidate_records_json}" | jq -r '
    sort_by(.domain)
    | .[]
    | "\(.domain)\t\(.ip)"
  '
)"

if [[ -z "${desired_records}" && "${state_managed}" == false ]]; then
  printf 'Error: no desired records resolved from nginx virtualHosts\n' >&2
  exit 1
fi

auth_payload="$(jq -cn --arg password "${PIHOLE_CREDENTIAL}" '{ password: $password }')"
auth_json="$(
  printf '%s' "${auth_payload}" |
    curl -fsS -X POST "${PIHOLE_URL%/}/api/auth" \
      -H 'Content-Type: application/json' \
      --data-binary @-
)"

if [[ "$(printf '%s' "${auth_json}" | jq -r '.session.valid // false')" != true ]]; then
  printf 'Error: Pi-hole authentication failed\n' >&2
  exit 1
fi

PIHOLE_SID="$(printf '%s' "${auth_json}" | jq -r '.session.sid // empty')"
PIHOLE_AUTH_ARGS=()
if [[ -n "${PIHOLE_SID}" ]]; then
  PIHOLE_AUTH_ARGS=(-H "X-FTL-SID: ${PIHOLE_SID}")
fi

cleanup() {
  if [[ -n "${PIHOLE_SID}" ]]; then
    curl -fsS -X DELETE "${PIHOLE_URL%/}/api/auth" \
      "${PIHOLE_AUTH_ARGS[@]}" >/dev/null || true
  fi
}
trap cleanup EXIT

existing_json="$(curl -fsS "${PIHOLE_URL%/}/api/config/dns/hosts" "${PIHOLE_AUTH_ARGS[@]}")"
existing_hosts_json="$(printf '%s' "${existing_json}" | jq -c '.config.dns.hosts // []')"
existing_records="$(
  printf '%s' "${existing_hosts_json}" | jq -r '
    .[]
    | capture("^\\s*(?<ip>\\S+)\\s+(?<domain>\\S+)\\s*$")?
    | select(. != null)
    | "\(.domain)\t\(.ip)"
  '
)"

complex_conflicts="$(
  printf '%s' "${existing_hosts_json}" | jq -r --argjson managed "${conflict_domains_json}" '
    .[]
    | capture("^\\s*(?<ip>\\S+)\\s+(?<names>.+?)\\s*$")?
    | select(. != null)
    | (.names | [splits("\\s+")]) as $names
    | select(($names | length) > 1)
    | select(any($names[]; . as $name | ($managed | index($name)) != null))
    | "\(.ip) \(.names)"
  '
)"

if [[ -n "${complex_conflicts}" ]]; then
  printf 'Error: managed domains occur in multi-name Pi-hole host records:\n%s\n' "${complex_conflicts}" >&2
  printf 'Split those records into one domain per entry before syncing.\n' >&2
  exit 1
fi

declare -A existing_ip_by_domain=()
while IFS=$'\t' read -r domain ip; do
  [[ -n "${domain}" ]] || continue
  existing_ip_by_domain["${domain}"]="${ip}"
done <<<"${existing_records}"

declare -A desired_ip_by_domain=()
while IFS=$'\t' read -r domain ip; do
  [[ -n "${domain}" ]] || continue
  desired_ip_by_domain["${domain}"]="${ip}"
done <<<"${desired_records}"

declare -A previously_managed_domain=()
while IFS= read -r domain; do
  [[ -n "${domain}" ]] || continue
  previously_managed_domain["${domain}"]=true
done < <(printf '%s' "${previous_managed_domains_json}" | jq -r '.[]')

mapfile -t managed_zones < <(
  printf '%s\n' "${desired_records}" |
    cut -f1 |
    awk -F. 'NF > 1 { sub(/^[^.]+\./, ""); print }' |
    sort -u
)

is_managed_domain() {
  local candidate="$1"
  local zone
  for zone in "${managed_zones[@]}"; do
    if [[ "${candidate}" == *."${zone}" ]]; then
      return 0
    fi
  done
  return 1
}

adds=0
updates=0
unchanged=0
deletes=0

printf 'Pi-hole URL: %s\n' "${PIHOLE_URL}"
printf 'Mode: %s\n' "$([[ "${APPLY}" == true ]] && printf 'apply' || printf 'dry-run')"
printf 'Managed nginx domains: %d\n' "$(printf '%s' "${candidate_records_json}" | jq 'length')"
if [[ "${state_managed}" == true ]]; then
  printf 'Previously managed domains: %d\n' "$(printf '%s' "${previous_managed_domains_json}" | jq 'length')"
fi

while IFS=$'\t' read -r domain desired_ip; do
  [[ -n "${domain}" ]] || continue

  current_ip="${existing_ip_by_domain[${domain}]:-}"

  if [[ -z "${current_ip}" ]]; then
    adds=$((adds + 1))
    printf '[ADD] %s -> %s\n' "${domain}" "${desired_ip}"

    continue
  fi

  if [[ "${current_ip}" != "${desired_ip}" ]]; then
    updates=$((updates + 1))
    printf '[UPD] %s: %s -> %s\n' "${domain}" "${current_ip}" "${desired_ip}"

    continue
  fi

  unchanged=$((unchanged + 1))
  printf '[OK ] %s -> %s\n' "${domain}" "${desired_ip}"
done <<<"${desired_records}"

if [[ "${PRUNE_MANAGED}" == true ]]; then
  while IFS=$'\t' read -r domain current_ip; do
    [[ -n "${domain}" ]] || continue

    should_prune=false
    if [[ "${state_managed}" == true ]]; then
      [[ -n "${previously_managed_domain[${domain}]:-}" ]] && should_prune=true
    elif is_managed_domain "${domain}"; then
      should_prune=true
    fi

    if [[ "${should_prune}" == true && -z "${desired_ip_by_domain[${domain}]:-}" ]]; then
      deletes=$((deletes + 1))
      printf '[DEL] %s -> %s (managed prune)\n' "${domain}" "${current_ip}"

    fi
  done <<<"${existing_records}"
fi

printf 'Summary: add=%d update=%d delete=%d unchanged=%d\n' "${adds}" "${updates}" "${deletes}" "${unchanged}"

if [[ "${APPLY}" == true && $((adds + updates + deletes)) -gt 0 ]]; then
  managed_zones_json="$(printf '%s\n' "${managed_zones[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
  final_hosts_json="$(
    jq -cn \
      --argjson existing "${existing_hosts_json}" \
      --argjson desired "${candidate_records_json}" \
      --argjson previous "${previous_managed_domains_json}" \
      --argjson zones "${managed_zones_json}" \
      --argjson stateManaged "${state_managed}" \
      --argjson prune "${PRUNE_MANAGED}" '
        ($desired | map(.domain)) as $desired_domains
        | $previous as $previous_domains
        | def managed_zone($domain):
            $zones | any(. as $zone | $domain | endswith("." + $zone));
        [
          $existing[]
          | . as $record
          | ((capture("^\\s*(?<ip>\\S+)\\s+(?<domain>\\S+)\\s*$")?) // null) as $parsed
          | select(
              $parsed == null
              or (
                ($desired_domains | index($parsed.domain)) == null
                and (
                  ($prune | not)
                  or (
                    if $stateManaged
                    then (($previous_domains | index($parsed.domain)) == null)
                    else (managed_zone($parsed.domain) | not)
                    end
                  )
                )
              )
            )
          | $record
        ]
        + ($desired | sort_by(.domain) | map("\(.ip) \(.domain)"))
      '
  )"
  update_payload="$(jq -cn --argjson hosts "${final_hosts_json}" '{ config: { dns: { hosts: $hosts } } }')"

  curl -fsS -X PATCH "${PIHOLE_URL%/}/api/config" \
    "${PIHOLE_AUTH_ARGS[@]}" \
    -H 'Content-Type: application/json' \
    --data-binary "${update_payload}" >/dev/null
  printf 'Pi-hole DNS hosts updated.\n'
elif [[ "${APPLY}" == true ]]; then
  printf 'No Pi-hole changes required.\n'
else
  printf 'Dry-run complete. Re-run with --apply to perform changes.\n'
fi

if [[ "${APPLY}" == true && -n "${STATE_FILE}" ]]; then
  state_directory="$(dirname "${STATE_FILE}")"
  mkdir -p "${state_directory}"
  temporary_state="$(mktemp "${state_directory}/.managed-domains.XXXXXX")"
  trap 'rm -f "${temporary_state}"; cleanup' EXIT
  printf '%s\n' "${current_managed_domains_json}" >"${temporary_state}"
  chmod 0600 "${temporary_state}"
  mv -f "${temporary_state}" "${STATE_FILE}"
  trap cleanup EXIT
fi
