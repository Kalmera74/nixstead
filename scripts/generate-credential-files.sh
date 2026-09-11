#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-${REPO_ROOT}/secrets}}"
HOST_NAME="${NIXSTEAD_HOST:-}"

# shellcheck source=scripts/lib/nixstead.sh
source "${NIXSTEAD_LIB:-${REPO_ROOT}/scripts/lib/nixstead.sh}"

TARGET=""
CUSTOM_PATH=""
FORCE=false
BOOTSTRAP=false
CURRENT_TARGET=""
TEMPORARY_PATHS=()

CENTRAL_TARGETS=(
  authentik
  cifs
  devdb
  forgejo
  gitea
  linkwarden
  qbittorrent
  romm
  seafile
  snapotter
  swaparr
  tubearchivist
  vaultwarden
  wallabag
  homepage
)

cleanup() {
  local temporary_path=""
  for temporary_path in "${TEMPORARY_PATHS[@]}"; do
    if [[ -d "${temporary_path}" ]]; then
      rm -rf -- "${temporary_path}"
    else
      rm -f -- "${temporary_path}"
    fi
  done
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage:
  nixstead [--host <name>] credentials bootstrap [--force] [--bootstrap] <target|all> [custom-output-path]

Targets:
  authentik         -> authentik signing-key branch
  cifs             -> CIFS username/password branch in the host SOPS file
  devdb            -> development service credentials branch
  forgejo          -> Forgejo initial admin branch
  gitea            -> Gitea initial admin branch
  homepage         -> Homepage integration branch (normally post-install)
  linkwarden       -> Linkwarden application branch
  qbittorrent      -> qBittorrent Web UI branch
  romm             -> RomM application branch
  seafile          -> Seafile application branch
  snapotter        -> SnapOtter application branch
  swaparr          -> Swaparr API key branch
  tubearchivist    -> TubeArchivist application branch
  vaultwarden      -> Vaultwarden admin token branch
  wallabag         -> Wallabag database branch
  nextcloud-admin  -> Nextcloud admin pass file
  paperless-secret -> preseed Paperless before its first startup
  kavita-token     -> manually preseed the normally auto-generated Kavita token
  all              -> Generate branches required by enabled services

Options:
  --force          Allow overwriting an existing output file.
  --bootstrap      Create non-interactive placeholders for post-install secrets.

Examples:
  nixstead --host myhost credentials bootstrap homepage
  nixstead credentials bootstrap nextcloud-admin /tmp/nc-pass
  nixstead --host myhost credentials bootstrap all

Environment:
  NIXSTEAD_SECRETS_DIR  Directory containing <host>.yaml.
  NIXSTEAD_HOST         Required for host secrets and service-owned runtime paths.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    --bootstrap)
      BOOTSTRAP=true
      shift
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -z "${TARGET}" ]]; then
        TARGET="$1"
      elif [[ -z "${CUSTOM_PATH}" ]]; then
        CUSTOM_PATH="$1"
      else
        printf 'Error: too many positional arguments.\n' >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  usage
  exit 1
fi

if [[ "${TARGET}" == "all" && -n "${CUSTOM_PATH}" ]]; then
  printf 'Error: all does not accept a custom output path.\n' >&2
  exit 1
fi

if [[ "${TARGET}" == "homepage" || -z "${CUSTOM_PATH}" ]]; then
  nixstead_require_host
fi

random_alnum() {
  local length="$1"
  od -An -N "${length}" -tu1 /dev/urandom |
    awk 'BEGIN { chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" } { for (i = 1; i <= NF; i++) printf "%s", substr(chars, ($i % length(chars)) + 1, 1) }'
}

random_hex() {
  local length="$1"
  od -An -N "$((length / 2))" -tx1 /dev/urandom | tr -d '[:space:]'
}

prompt() {
  local label="$1"
  local default_value="$2"
  local secret="${3:-false}"
  local input=""

  if [[ "${secret}" == "true" ]]; then
    if [[ -n "${default_value}" ]]; then
      IFS= read -rsp "${label} [hidden, Enter keeps current/default]: " input
    else
      IFS= read -rsp "${label} [hidden]: " input
    fi
    echo >&2
  else
    if [[ -n "${default_value}" ]]; then
      IFS= read -rp "${label} [${default_value}]: " input
    else
      IFS= read -rp "${label}: " input
    fi
  fi

  if [[ -z "${input}" ]]; then
    printf '%s' "${default_value}"
  else
    printf '%s' "${input}"
  fi
}

prompt_for_enabled_service() {
  local output_variable="$1"
  local service_name="$2"
  local label="$3"
  local default_value="$4"
  local secret="${5:-false}"
  local value="${default_value}"

  if [[ "${HOMEPAGE_ENABLED_SERVICES[${service_name}]:-false}" == true ]]; then
    value="$(prompt "${label}" "${default_value}" "${secret}")"
  fi

  printf -v "${output_variable}" '%s' "${value}"
}

read_sops_value() {
  local input_path="$1"
  local expression="$2"
  local value=""

  [[ -f "${input_path}" ]] || return 0
  value="$(sops decrypt --output-type binary --extract "${expression}" "${input_path}" 2>/dev/null || true)"
  while [[ "${value}" == $'\n'* ]]; do
    value="${value#$'\n'}"
  done
  printf '%s' "${value}"
}

current_homepage_value() {
  local output_path="$1"
  local key="$2"

  read_sops_value "${output_path}" "[\"homepage\"][\"${key}\"]"
}

load_homepage_enabled_services() {
  local enabled_services=""
  local service_name=""

  command -v nix >/dev/null 2>&1 || {
    printf '%s\n' 'Error: nix is required to resolve enabled Homepage integrations.' >&2
    return 1
  }

  declare -gA HOMEPAGE_ENABLED_SERVICES=()
  # This is a Nix expression; its interpolation is intentionally literal here.
  # shellcheck disable=SC2016
  enabled_services="$(nixstead_config_apply_raw nixstead.serviceRegistry '
    registry:
      builtins.concatStringsSep "\n" (
        builtins.filter
          (name:
            let
              entry = registry.${name};
              widget = if entry.homepage == null then null else entry.homepage.widget or null;
            in
              entry.enabled
              && widget != null
              && (widget.secrets or {}) != {}
          )
          (builtins.attrNames registry)
      )
  ')"

  while IFS= read -r service_name; do
    [[ -n "${service_name}" ]] || continue
    HOMEPAGE_ENABLED_SERVICES["${service_name}"]=true
  done <<<"${enabled_services}"
}

is_central_target() {
  local candidate="$1"
  local central_target=""
  for central_target in "${CENTRAL_TARGETS[@]}"; do
    [[ "${candidate}" == "${central_target}" ]] && return 0
  done
  return 1
}

write_plain_secret_file() {
  local output_path="$1"
  local content="$2"
  local owner="${3:-}"
  local owner_uid parent

  if [[ -n "${owner}" ]]; then
    owner_uid="$(id -u -- "${owner}")" || return 1
    if [[ "${EUID}" != 0 && "${EUID}" != "${owner_uid}" ]]; then
      printf 'Error: run as root or %s to preseed this service-owned file.\n' "${owner}" >&2
      return 1
    fi
  fi

  if [[ -e "${output_path}" && "${FORCE}" != true ]]; then
    printf 'Error: output already exists: %s (pass --force to overwrite)\n' "${output_path}" >&2
    return 1
  fi

  parent="$(dirname "${output_path}")"
  if [[ -n "${owner}" && ! -d "${parent}" ]]; then
    install -d -m 0700 -o "${owner}" -- "${parent}"
  else
    mkdir -p "${parent}"
  fi
  umask 077
  printf '%s\n' "${content}" >"${output_path}"
  chmod 600 "${output_path}"
  if [[ -n "${owner}" ]]; then
    chown -- "${owner}" "${output_path}"
  fi
  echo "Wrote ${output_path}"
}

sops_branch_exists() {
  local input_path="$1"
  local branch="$2"
  [[ -f "${input_path}" ]] || return 1
  sops decrypt --extract "[\"${branch}\"]" "${input_path}" >/dev/null 2>&1
}

ensure_sops_file() {
  local output_path="$1"
  local temporary_file=""

  [[ -f "${output_path}" ]] && return 0
  [[ -f "${REPO_ROOT}/.sops.yaml" ]] || {
    printf 'Error: missing SOPS policy: %s/.sops.yaml\n' "${REPO_ROOT}" >&2
    return 1
  }

  mkdir -p "$(dirname "${output_path}")"
  temporary_file="$(mktemp)"
  TEMPORARY_PATHS+=("${temporary_file}")
  printf '{}\n' >"${temporary_file}"
  (
    cd "${REPO_ROOT}"
    sops --encrypt \
      --filename-override "secrets/$(basename "${output_path}")" \
      --input-type json \
      --output-type yaml \
      --output "${output_path}" \
      "${temporary_file}"
  )
  chmod 0644 "${output_path}"
  rm -f -- "${temporary_file}"
}

write_sops_domain() {
  local output_path="$1"
  local domain="$2"
  local json_content="$3"
  local temporary_directory=""
  local json_file=""

  if sops_branch_exists "${output_path}" "${domain}" && [[ "${FORCE}" != true ]]; then
    printf 'Error: encrypted branch already exists: %s in %s (pass --force to overwrite)\n' \
      "${domain}" "${output_path}" >&2
    return 1
  fi

  temporary_directory="$(mktemp -d)"
  TEMPORARY_PATHS+=("${temporary_directory}")
  json_file="${temporary_directory}/${domain}.json"
  printf '%s\n' "${json_content}" >"${json_file}"

  if [[ "${domain}" == homepage || "${domain}" == swaparr ]]; then
    python3 - "${json_file}" "${output_path}" "${domain}" <<'PYFILTER'
import json, subprocess, sys
from pathlib import Path
path, encrypted, domain = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
data = json.loads(path.read_text())
old = {}
if encrypted.exists():
    result = subprocess.run(['sops', 'decrypt', '--output-type', 'json', str(encrypted)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('Cannot read existing encrypted credentials; refusing replacement')
    old = json.loads(result.stdout).get(domain, {})
# These prompts own only the fields they generate. Preserve managed media
# keys and other integrations without maintaining a second service catalog.
path.write_text(json.dumps(old | data))
PYFILTER
  fi
  ensure_sops_file "${output_path}"
  sops set --value-file "${output_path}" "[\"${domain}\"]" "${json_file}"
  chmod 0644 "${output_path}"
  rm -rf -- "${temporary_directory}"
  printf 'Updated encrypted branch %s in %s\n' "${domain}" "${output_path}"
}

write_json_secret() {
  local output_path="$1"
  local content
  shift
  # Shell builtins deliver values on stdin; secrets never become Nix source,
  # external process arguments, or environment variables.
  content="$(printf '%s\0' "$@" | python3 -c '
import json, sys
fields = sys.stdin.buffer.read().decode().split("\0")[:-1]
if len(fields) % 2:
    raise SystemExit("Expected credential path/value pairs")
document = {}
for key, value in zip(fields[::2], fields[1::2]):
    parts = key.split("/")
    branch = document
    for part in parts[:-1]:
        branch = branch.setdefault(part, {})
    branch[parts[-1]] = value
json.dump(document, sys.stdout)
')"
  write_sops_domain "${output_path}" "${CURRENT_TARGET}" "${content}"
}

default_path_for() {
  local target="$1"
  local data_dir
  case "${target}" in
    authentik | cifs | devdb | forgejo | gitea | homepage | linkwarden | qbittorrent | romm | seafile | snapotter | swaparr | tubearchivist | vaultwarden | wallabag)
      printf '%s' "${SECRETS_DIR}/${HOST_NAME}.yaml"
      ;;
    nextcloud-admin)
      nixstead_config_raw services.nextcloud.config.adminpassFile
      ;;
    paperless-secret)
      command -v nix >/dev/null 2>&1 || {
        printf 'Error: nix is required to resolve the Paperless path\n' >&2
        return 1
      }
      data_dir="$(nixstead_config_raw services.paperless.dataDir)" || return 1
      [[ -n "${data_dir}" ]] || return 1
      if [[ -e "${data_dir}/nixos-paperless-secret-key.env" ]]; then
        printf 'Paperless already has an active key; use services.paperless.environmentFile for an explicit replacement.\n' >&2
        return 1
      fi
      printf '%s/nixos-paperless-secret-key' "${data_dir}"
      ;;
    kavita-token)
      command -v nix >/dev/null 2>&1 || {
        printf 'Error: nix is required to resolve the Kavita path\n' >&2
        return 1
      }
      nixstead_config_raw nixstead.services.media.kavita.tokenKeyFile
      ;;
    *) return 1 ;;
  esac
}

for command_name in awk basename chmod chown dirname id install mkdir mktemp od python3 rm sops tr; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
done

generate_homepage() {
  local output_path="$1"
  if [[ "${BOOTSTRAP}" == true ]]; then
    echo "Generating Homepage bootstrap placeholders..."
  else
    echo "Configuring post-install Homepage integrations..."
  fi

  load_homepage_enabled_services

  local pihole_api_key paperless_api_key nextcloud_token linkwarden_api_key
  local jellyfin_api_key komga_username komga_password
  local audiobookshelf_api_key kavita_api_key immich_api_key tubearchivist_api_key
  local readarr_api_key
  local grafana_username grafana_password gitea_api_token
  local proxmox_username proxmox_password truenas_api_key

  if [[ "${BOOTSTRAP}" == true ]]; then
    pihole_api_key=""
    paperless_api_key=""
    nextcloud_token=""
    linkwarden_api_key=""
    jellyfin_api_key=""
    komga_username=""
    komga_password=""
    audiobookshelf_api_key=""
    kavita_api_key=""
    immich_api_key=""
    tubearchivist_api_key=""
    readarr_api_key=""
    grafana_username=""
    grafana_password=""
    gitea_api_token=""
    proxmox_username=""
    proxmox_password=""
    truenas_api_key=""
  else
    prompt_for_enabled_service pihole_api_key pihole "Pi-hole password/application password" "$(current_homepage_value "${output_path}" piholeApiKey)" true
    prompt_for_enabled_service paperless_api_key paperless "Paperless API key" "$(current_homepage_value "${output_path}" paperlessApiKey)" true
    prompt_for_enabled_service nextcloud_token nextcloud "Nextcloud NC-Token" "$(current_homepage_value "${output_path}" nextcloudToken)" true
    prompt_for_enabled_service linkwarden_api_key linkwarden "Linkwarden access token" "$(current_homepage_value "${output_path}" linkwardenApiKey)" true
    prompt_for_enabled_service jellyfin_api_key jellyfin "Jellyfin API key" "$(current_homepage_value "${output_path}" jellyfinApiKey)" true
    prompt_for_enabled_service komga_username komga "Komga username" "$(current_homepage_value "${output_path}" komgaUsername)"
    prompt_for_enabled_service komga_password komga "Komga password" "$(current_homepage_value "${output_path}" komgaPassword)" true
    prompt_for_enabled_service audiobookshelf_api_key audiobookshelf "Audiobookshelf API key" "$(current_homepage_value "${output_path}" audiobookshelfApiKey)" true
    prompt_for_enabled_service kavita_api_key kavita "Kavita API key" "$(current_homepage_value "${output_path}" kavitaApiKey)" true
    prompt_for_enabled_service immich_api_key immich "Immich API key" "$(current_homepage_value "${output_path}" immichApiKey)" true
    prompt_for_enabled_service tubearchivist_api_key tubearchivist "TubeArchivist API token" "$(current_homepage_value "${output_path}" tubearchivistApiKey)" true
    prompt_for_enabled_service readarr_api_key readarr "Readarr API key" "$(current_homepage_value "${output_path}" readarrApiKey)" true
    prompt_for_enabled_service grafana_username grafana "Grafana username" "$(current_homepage_value "${output_path}" grafanaUsername)"
    prompt_for_enabled_service grafana_password grafana "Grafana password" "$(current_homepage_value "${output_path}" grafanaPassword)" true
    prompt_for_enabled_service gitea_api_token gitea "Gitea API token" "$(current_homepage_value "${output_path}" giteaApiToken)" true
    prompt_for_enabled_service proxmox_username proxmox "Proxmox username" "$(current_homepage_value "${output_path}" proxmoxUsername)"
    prompt_for_enabled_service proxmox_password proxmox "Proxmox password/token" "$(current_homepage_value "${output_path}" proxmoxPassword)" true
    prompt_for_enabled_service truenas_api_key truenas "TrueNAS API key" "$(current_homepage_value "${output_path}" truenasApiKey)" true
  fi

  write_json_secret "${output_path}" \
    piholeApiKey "${pihole_api_key}" \
    paperlessApiKey "${paperless_api_key}" \
    nextcloudToken "${nextcloud_token}" \
    linkwardenApiKey "${linkwarden_api_key}" \
    jellyfinApiKey "${jellyfin_api_key}" \
    komgaUsername "${komga_username}" \
    komgaPassword "${komga_password}" \
    audiobookshelfApiKey "${audiobookshelf_api_key}" \
    kavitaApiKey "${kavita_api_key}" \
    immichApiKey "${immich_api_key}" \
    tubearchivistApiKey "${tubearchivist_api_key}" \
    readarrApiKey "${readarr_api_key}" \
    grafanaUsername "${grafana_username}" \
    grafanaPassword "${grafana_password}" \
    giteaApiToken "${gitea_api_token}" \
    proxmoxUsername "${proxmox_username}" \
    proxmoxPassword "${proxmox_password}" \
    truenasApiKey "${truenas_api_key}"
}

generate_devdb() {
  local output_path="$1"
  echo "Generating devdb secrets..."

  local postgres_user postgres_password mongodb_password
  local redis_user redis_password rabbitmq_user rabbitmq_password
  local grafana_user grafana_password grafana_secret_key
  local pgadmin_password

  postgres_user="$(prompt "PostgreSQL root user" "root")"
  postgres_password="$(prompt "PostgreSQL root password" "" true)"
  mongodb_password="$(prompt "MongoDB root password" "" true)"
  redis_user="$(prompt "Redis root user" "root")"
  redis_password="$(prompt "Redis root password" "" true)"
  rabbitmq_user="$(prompt "RabbitMQ root user" "root")"
  rabbitmq_password="$(prompt "RabbitMQ root password" "" true)"
  grafana_user="$(prompt "Grafana admin user" "admin")"
  grafana_password="$(prompt "Grafana admin password" "" true)"
  grafana_secret_key="$(prompt "Grafana secret key (blank = auto-generate)" "" true)"
  pgadmin_password="$(prompt "pgAdmin initial password" "" true)"

  if [[ -z "${grafana_secret_key}" ]]; then
    grafana_secret_key="$(random_alnum 64)"
  fi

  write_json_secret "${output_path}" \
    postgresql/rootUser "${postgres_user}" \
    postgresql/rootPassword "${postgres_password}" \
    mongodb/rootPassword "${mongodb_password}" \
    redis/rootUser "${redis_user}" \
    redis/rootPassword "${redis_password}" \
    rabbitmq/rootUser "${rabbitmq_user}" \
    rabbitmq/rootPassword "${rabbitmq_password}" \
    grafana/adminUser "${grafana_user}" \
    grafana/adminPassword "${grafana_password}" \
    grafana/secretKey "${grafana_secret_key}" \
    pgadmin/initialPassword "${pgadmin_password}"
}

generate_authentik() {
  local output_path="$1"
  echo "Generating authentik secrets..."

  local secret_key
  secret_key="$(prompt "authentik secret key (blank = auto-generate)" "" true)"
  if [[ -z "${secret_key}" ]]; then
    secret_key="$(random_alnum 60)"
    echo "Generated random authentik secret key."
  fi

  write_json_secret "${output_path}" \
    secretKey "${secret_key}"
}

generate_git_service() {
  local output_path="$1"
  local service_name="$2"
  echo "Generating ${service_name} secrets..."

  local admin_username admin_email admin_password
  admin_username="$(prompt "${service_name} initial admin username" "")"
  admin_email="$(prompt "${service_name} initial admin email" "")"
  admin_password="$(prompt "${service_name} initial admin password" "" true)"

  write_json_secret "${output_path}" \
    initialAdmin/username "${admin_username}" \
    initialAdmin/email "${admin_email}" \
    initialAdmin/password "${admin_password}"
}

generate_forgejo() {
  generate_git_service "$1" Forgejo
}

generate_gitea() {
  generate_git_service "$1" Gitea
}

generate_cifs() {
  local output_path="$1"
  echo "Generating CIFS secrets..."

  local username password domain
  username="$(prompt "CIFS username" "")"
  password="$(prompt "CIFS password" "" true)"
  domain="$(prompt "CIFS domain/workgroup (optional)" "")"

  write_json_secret "${output_path}" \
    username "${username}" \
    password "${password}" \
    domain "${domain}"
}

generate_linkwarden() {
  local output_path="$1"
  echo "Generating Linkwarden secrets..."

  local nextauth_secret postgres_password meili_master_key
  nextauth_secret="$(prompt "NextAuth secret (blank = auto-generate)" "" true)"
  postgres_password="$(prompt "PostgreSQL password (blank = auto-generate)" "" true)"
  meili_master_key="$(prompt "Meilisearch master key (blank = auto-generate)" "" true)"
  [[ -n "${nextauth_secret}" ]] || nextauth_secret="$(random_alnum 64)"
  [[ -n "${postgres_password}" ]] || postgres_password="$(random_alnum 48)"
  [[ -n "${meili_master_key}" ]] || meili_master_key="$(random_alnum 64)"

  write_json_secret "${output_path}" \
    nextAuthSecret "${nextauth_secret}" \
    postgresPassword "${postgres_password}" \
    meiliMasterKey "${meili_master_key}"
}

generate_qbittorrent() {
  local output_path="$1"
  echo "Generating qBittorrent secrets..."

  local username password
  username="$(prompt "qBittorrent Web UI username" "arr")"
  password="$(prompt "qBittorrent Web UI password (blank = auto-generate)" "" true)"
  [[ -n "${password}" ]] || password="$(random_alnum 48)"

  write_json_secret "${output_path}" \
    username "${username}" \
    password "${password}"
}

generate_romm() {
  local output_path="$1"
  echo "Generating RomM secrets..."

  local auth_secret db_password db_root_password
  local igdb_client_id igdb_client_secret moby_api_key screenscraper_user
  local screenscraper_password steamgriddb_api_key retroachievements_api_key

  auth_secret="$(prompt "RomM auth secret (blank = auto-generate)" "" true)"
  db_password="$(prompt "RomM database password (blank = auto-generate)" "" true)"
  db_root_password="$(prompt "RomM database root password (blank = auto-generate)" "" true)"
  igdb_client_id="$(prompt "IGDB client ID" "" true)"
  igdb_client_secret="$(prompt "IGDB client secret" "" true)"
  moby_api_key="$(prompt "MobyGames API key" "" true)"
  screenscraper_user="$(prompt "ScreenScraper username" "")"
  screenscraper_password="$(prompt "ScreenScraper password" "" true)"
  steamgriddb_api_key="$(prompt "SteamGridDB API key" "" true)"
  retroachievements_api_key="$(prompt "RetroAchievements API key" "" true)"

  [[ -n "${auth_secret}" ]] || auth_secret="$(random_hex 64)"
  [[ -n "${db_password}" ]] || db_password="$(random_alnum 48)"
  [[ -n "${db_root_password}" ]] || db_root_password="$(random_alnum 48)"

  write_json_secret "${output_path}" \
    authSecretKey "${auth_secret}" \
    dbPassword "${db_password}" \
    dbRootPassword "${db_root_password}" \
    igdbClientId "${igdb_client_id}" \
    igdbClientSecret "${igdb_client_secret}" \
    mobyGamesApiKey "${moby_api_key}" \
    screenscraperUser "${screenscraper_user}" \
    screenscraperPassword "${screenscraper_password}" \
    steamGridDbApiKey "${steamgriddb_api_key}" \
    retroAchievementsApiKey "${retroachievements_api_key}"
}

generate_seafile() {
  local output_path="$1"
  echo "Generating Seafile secrets..."

  local admin_email admin_password db_root_password seafile_domain
  seafile_domain="$(nixstead_config_raw nixstead.services.productivity.seafile.domain)"
  admin_email="$(prompt "Seafile admin email" "admin@${seafile_domain}")"
  admin_password="$(prompt "Seafile admin password (blank = auto-generate)" "" true)"
  db_root_password="$(prompt "Seafile database root password (blank = auto-generate)" "" true)"
  [[ -n "${admin_password}" ]] || admin_password="$(random_alnum 48)"
  [[ -n "${db_root_password}" ]] || db_root_password="$(random_alnum 48)"

  write_json_secret "${output_path}" \
    adminEmail "${admin_email}" \
    adminPassword "${admin_password}" \
    dbRootPassword "${db_root_password}"
}

generate_snapotter() {
  local output_path="$1"
  echo "Generating SnapOtter secrets..."

  local default_password data_encryption_key postgres_password redis_password
  default_password="$(prompt "SnapOtter initial admin password (blank = auto-generate)" "$(read_sops_value "${output_path}" '["snapotter"]["defaultPassword"]')" true)"
  data_encryption_key="$(prompt "SnapOtter data encryption key (blank = auto-generate)" "$(read_sops_value "${output_path}" '["snapotter"]["dataEncryptionKey"]')" true)"
  postgres_password="$(prompt "SnapOtter PostgreSQL password (blank = auto-generate)" "$(read_sops_value "${output_path}" '["snapotter"]["postgresPassword"]')" true)"
  redis_password="$(prompt "SnapOtter Redis password (blank = auto-generate)" "$(read_sops_value "${output_path}" '["snapotter"]["redisPassword"]')" true)"
  [[ -n "${default_password}" ]] || default_password="$(random_alnum 48)"
  [[ -n "${data_encryption_key}" ]] || data_encryption_key="$(random_hex 64)"
  [[ -n "${postgres_password}" ]] || postgres_password="$(random_alnum 48)"
  [[ -n "${redis_password}" ]] || redis_password="$(random_alnum 48)"

  write_json_secret "${output_path}" \
    defaultPassword "${default_password}" \
    dataEncryptionKey "${data_encryption_key}" \
    postgresPassword "${postgres_password}" \
    redisPassword "${redis_password}"
}

generate_swaparr() {
  local output_path="$1"
  echo "Generating Swaparr secrets..."

  local readarr_api_key
  if [[ "${BOOTSTRAP}" == true ]]; then
    readarr_api_key=""
  else
    readarr_api_key="$(prompt "Readarr API key" "$(read_sops_value "${output_path}" '["swaparr"]["readarrApiKey"]')" true)"
  fi

  write_json_secret "${output_path}" \
    readarrApiKey "${readarr_api_key}"
}

generate_tubearchivist() {
  local output_path="$1"
  echo "Generating TubeArchivist secrets..."

  local username password elastic_password
  username="$(prompt "TubeArchivist username" "tubearchivist")"
  password="$(prompt "TubeArchivist password (blank = auto-generate)" "" true)"
  elastic_password="$(prompt "Elasticsearch password (blank = auto-generate)" "" true)"
  [[ -n "${password}" ]] || password="$(random_alnum 48)"
  [[ -n "${elastic_password}" ]] || elastic_password="$(random_alnum 48)"

  write_json_secret "${output_path}" \
    username "${username}" \
    password "${password}" \
    elasticPassword "${elastic_password}"
}

generate_vaultwarden() {
  local output_path="$1"
  echo "Generating vaultwarden secrets..."

  local admin_token
  admin_token="$(prompt "Vaultwarden admin token (blank = auto-generate)" "" true)"
  if [[ -z "${admin_token}" ]]; then
    admin_token="$(random_alnum 64)"
    echo "Generated random Vaultwarden admin token."
  fi

  write_json_secret "${output_path}" \
    adminToken "${admin_token}"
}

generate_wallabag() {
  local output_path="$1"
  echo "Generating Wallabag secrets..."

  local database_password
  database_password="$(prompt "Wallabag database password (blank = auto-generate)" "" true)"
  [[ -n "${database_password}" ]] || database_password="$(random_alnum 48)"

  write_json_secret "${output_path}" \
    databasePassword "${database_password}"
}

generate_nextcloud_admin() {
  local output_path="$1"
  echo "Generating nextcloud admin password file..."

  local admin_password
  admin_password="$(prompt "Nextcloud admin password (blank = auto-generate)" "" true)"
  if [[ -z "${admin_password}" ]]; then
    admin_password="$(random_alnum 48)"
    echo "Generated random Nextcloud admin password."
  fi

  write_plain_secret_file "${output_path}" "${admin_password}"
}

generate_paperless_secret() {
  local output_path="$1"
  local owner=""
  if [[ -z "${CUSTOM_PATH}" ]]; then
    owner="$(nixstead_config_raw services.paperless.user)" || return 1
    [[ -n "${owner}" ]] || {
      echo 'Could not resolve the configured Paperless account.' >&2
      return 1
    }
  fi
  echo "Generating paperless secret key file..."

  local secret_key
  secret_key="$(prompt "Paperless secret key (blank = auto-generate)" "" true)"
  if [[ -z "${secret_key}" ]]; then
    secret_key="$(random_alnum 64)"
    echo "Generated random Paperless secret key."
  fi
  # The native legacy migration copies this value into an environment file.
  if [[ "${secret_key}" == *[!a-zA-Z0-9_-]* ]]; then
    echo 'Paperless preseeds must contain only letters, digits, underscores or hyphens; use services.paperless.environmentFile for other values.' >&2
    return 1
  fi

  write_plain_secret_file "${output_path}" "${secret_key}" "${owner}"
}

generate_kavita_token() {
  local output_path="$1"
  echo "Generating kavita token key file..."

  local token_key
  token_key="$(prompt "Kavita token key (blank = auto-generate)" "" true)"
  if [[ -z "${token_key}" ]]; then
    token_key="$(random_alnum 64)"
    echo "Generated random Kavita token key."
  fi

  write_plain_secret_file "${output_path}" "${token_key}"
}

generate_target() {
  local target="$1"
  local output_path="${2:-}"
  CURRENT_TARGET="${target}"

  if [[ -z "${output_path}" ]]; then
    output_path="$(default_path_for "${target}")" || {
      echo "Could not resolve the default output path for target: ${target}" >&2
      exit 1
    }
  fi

  if [[ -n "${output_path}" && "${output_path}" != /* ]] &&
    { [[ -n "${CUSTOM_PATH}" ]] || is_central_target "${target}"; }; then
    output_path="${PWD}/${output_path}"
  fi
  if [[ "${output_path}" != /* || "${output_path}" == / || "${output_path}" == /nix/store/* ]]; then
    echo "Credential destination must be an absolute writable file path outside /nix/store." >&2
    exit 1
  fi

  if is_central_target "${target}"; then
    if sops_branch_exists "${output_path}" "${target}" && [[ "${FORCE}" != true ]]; then
      printf 'Error: encrypted branch already exists: %s in %s (pass --force to overwrite)\n' \
        "${target}" "${output_path}" >&2
      exit 1
    fi
  elif [[ -e "${output_path}" && "${FORCE}" != true ]]; then
    printf 'Error: output already exists: %s (pass --force to overwrite)\n' "${output_path}" >&2
    exit 1
  fi

  case "${target}" in
    authentik) generate_authentik "${output_path}" ;;
    cifs) generate_cifs "${output_path}" ;;
    homepage) generate_homepage "${output_path}" ;;
    devdb) generate_devdb "${output_path}" ;;
    forgejo) generate_forgejo "${output_path}" ;;
    gitea) generate_gitea "${output_path}" ;;
    linkwarden) generate_linkwarden "${output_path}" ;;
    qbittorrent) generate_qbittorrent "${output_path}" ;;
    romm) generate_romm "${output_path}" ;;
    seafile) generate_seafile "${output_path}" ;;
    snapotter) generate_snapotter "${output_path}" ;;
    swaparr) generate_swaparr "${output_path}" ;;
    tubearchivist) generate_tubearchivist "${output_path}" ;;
    vaultwarden) generate_vaultwarden "${output_path}" ;;
    wallabag) generate_wallabag "${output_path}" ;;
    nextcloud-admin) generate_nextcloud_admin "${output_path}" ;;
    paperless-secret) generate_paperless_secret "${output_path}" ;;
    kavita-token) generate_kavita_token "${output_path}" ;;
    *)
      echo "Unknown target: ${target}"
      usage
      exit 1
      ;;
  esac
}

if [[ "${TARGET}" == "all" ]]; then
  required_secrets="$({
    nixstead_config_json nixstead.serviceRegistry |
      jq -r '[to_entries[] | select(.value.enabled) | .value.secrets[]] | unique[]'
  })"
  required_targets=()
  while IFS= read -r target; do
    [[ -n "${target}" ]] || continue
    if ! is_central_target "${target}"; then
      printf 'Error: enabled services require unsupported credential target: %s\n' "${target}" >&2
      exit 1
    fi
    required_targets+=("${target}")
  done <<<"${required_secrets}"

  if [[ ${#required_targets[@]} -eq 0 ]]; then
    echo "No enabled service requires a generated credential branch."
    exit 0
  fi

  if [[ "${FORCE}" != true ]]; then
    for target in "${required_targets[@]}"; do
      output_path="$(default_path_for "${target}")"
      if sops_branch_exists "${output_path}" "${target}"; then
        printf 'Error: encrypted branch already exists: %s in %s (pass --force to overwrite all targets)\n' \
          "${target}" "${output_path}" >&2
        exit 1
      fi
    done
  fi

  requested_bootstrap="${BOOTSTRAP}"
  for target in "${required_targets[@]}"; do
    BOOTSTRAP="${requested_bootstrap}"
    if [[ "${target}" == "homepage" || "${target}" == "swaparr" ]]; then
      BOOTSTRAP=true
    fi
    generate_target "${target}"
  done
else
  generate_target "${TARGET}" "${CUSTOM_PATH}"
fi

echo "Done."
