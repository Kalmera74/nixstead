#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="${NIXSTEAD_SCRIPT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="${NIXSTEAD_REPOSITORY_ROOT:-$(cd "${SCRIPT_ROOT}/.." && pwd)}"
HOST_NAME="${NIXSTEAD_HOST:-}"
SECRETS_DIR="${NIXSTEAD_SECRETS_DIR:-${NIXCONFIG_SECRETS_DIR:-}}"
MEDIA_ENABLED="${NIXSTEAD_MEDIA_ENABLED:-true}"

usage() {
  cat <<'EOF'
Usage: nixstead [global-options] <command> [arguments]

Commands:
  setup <wizard|sops>           Create, switch, or enroll a host
  check <preflight|runtime|secrets>
                                Validate configuration or runtime state
  credentials <command>         Bootstrap, configure, inspect, sync, or rotate credentials
  images <list|set|reset|diff>  Manage digest-pinned container images
  backup <create|verify|restore>
                                Operate registry-driven service backups
  dns sync                      Reconcile registry DNS participants with Pi-hole
  forge mirror                  Import GitHub repositories as Forgejo mirrors
  media <command>               Optional media-library tools

Global options:
  --host <name>                 Select a NixOS configuration
  --repo-root <path>            Select the mutable Nixstead checkout
  --secrets-dir <path>          Select the encrypted secrets directory
  -h, --help                    Show this help

Use `help`, `-h`, or `--help` at any command level. For example:
  nixstead media help
  nixstead media rom-import help
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_no_args() {
  (($# == 0)) || die "unexpected argument: $1"
}

is_help_token() {
  case "${1:-}" in
    help | -h | --help) return 0 ;;
    *) return 1 ;;
  esac
}

leaf_help_requested() {
  (($# == 1)) && is_help_token "$1"
}

require_host() {
  [[ -n "${HOST_NAME}" ]] || die "select a host with --host or NIXSTEAD_HOST"
}

run_with_host_and_secrets() {
  local script="$1"
  shift
  "${SCRIPT_ROOT}/${script}" "${HOST_NAME}" "${SECRETS_DIR}" "$@"
}

usage_setup() {
  cat <<'EOF'
Usage:
  nixstead setup wizard [options] [target]
  nixstead --host <name> setup sops [options]

Commands:
  wizard  Create a host interactively or validate and switch an existing target
  sops    Enroll administrator and host recipients in the SOPS policy

Run `nixstead setup <command> help` for command options.
EOF
}

usage_setup_wizard() {
  cat <<'EOF'
Usage: nixstead setup wizard [options] [target]

Create a new host interactively, or validate and switch an existing flake target.

Arguments:
  target                    Existing flake target to validate and switch

Options:
  -i, --interactive, --new-host
                            Create a new host interactively
  --hardware-config <path>  Hardware configuration source for a new host
  --state-version <YY.MM>   Original NixOS state version
  --configuration <path>    Installed configuration to inspect
  --output <directory>      Create a standalone consumer flake (recommended)
  --repo-local              Create hosts/<name> inside a Nixstead checkout
  --nixstead-url <url>      Dependency URL written to a standalone flake
  --generate-only           Create and validate without switching
  --skip-healthcheck        Skip the pre-switch health check
  -h, --help                Show this help
EOF
}

usage_check() {
  cat <<'EOF'
Usage:
  nixstead check preflight
  nixstead check runtime
  nixstead check secrets <homepage|store>

Commands:
  preflight  Validate evaluation, required paths, and encrypted secret branches
  runtime    Check mounts, units, endpoints, and enabled database services
  secrets    Validate Homepage keys or scan the Nix store for secret leaks

Run `nixstead check <command> help` for command details.
EOF
}

usage_check_secrets() {
  cat <<'EOF'
Usage:
  nixstead check secrets homepage
  nixstead check secrets store

Commands:
  homepage  Compare encrypted Homepage keys with the tracked schema
  store     Scan an evaluated system closure for decrypted secret values

Run `nixstead check secrets <command> help` for command details.
EOF
}

usage_credentials() {
  cat <<'EOF'
Usage:
  nixstead credentials bootstrap [--force] [--bootstrap] <target|all> [output]
  nixstead credentials configure homepage
  nixstead credentials validate homepage
  nixstead credentials list
  nixstead credentials show <service|sops:path/to/key> [--runtime]
  nixstead credentials sync [service] [--from <source>] [--restore] [--dry-run]
  nixstead credentials rotate <service> [--dry-run]

Commands:
  bootstrap  Generate encrypted credentials required by a service or host
  configure  Prompt for post-install integration credentials
  validate   Compare integration credentials with the tracked schema
  list       List available services and encrypted keys without values
  show       Reveal one explicitly selected credential
  sync       Reconcile canonical and application credentials
  rotate     Replace one managed service credential

Run `nixstead credentials <command> help` for command options.
EOF
}

usage_credentials_configure() {
  cat <<'EOF'
Usage: nixstead credentials configure homepage

Targets:
  homepage  Prompt for unmanaged Homepage integration credentials
EOF
}

usage_credentials_validate() {
  cat <<'EOF'
Usage: nixstead credentials validate homepage

Targets:
  homepage  Compare encrypted Homepage keys with the tracked schema
EOF
}

usage_images() {
  cat <<'EOF'
Usage:
  nixstead images list
  nixstead images set [options] <service> <component> <image> [...]
  nixstead images reset [options] <service> <component> [...]
  nixstead images diff

Commands:
  list   Show resolved image references and overrides
  set    Resolve and save one or more digest-pinned overrides
  reset  Remove one or more generated overrides
  diff   Show pending changes to the generated override file

Run `nixstead images <command> help` for command options.
EOF
}

usage_backup() {
  cat <<'EOF'
Usage:
  nixstead backup create
  nixstead backup verify [archive-name]
  nixstead backup restore latest --apply [options]
  nixstead backup restore borg <archive-name> --apply [options]

Commands:
  create   Create an encrypted service-state archive
  verify   Verify archive data and declared recovery artifacts
  restore  Restore the latest copy or a selected Borg archive

Run `nixstead backup <command> help` for command options.
EOF
}

usage_media() {
  cat <<'EOF'
Usage:
  nixstead media transcode [options] <input-dir> [output-dir]
  nixstead media hardlinks <compare|shared|same-file> <paths...>
  nixstead media rom-import [options] <batocera-root> <romm-root>
  nixstead media kavita-import [--apply] <directory>

Commands:
  transcode     Convert a video library to efficient AV1 or HEVC media
  hardlinks     Compare hardlink trees or find files sharing an inode
  rom-import    Copy a Batocera ROM library into RomM's platform layout
  kavita-import Organize loose books into Kavita-compatible folders

Run `nixstead media <command> help` for command options.
EOF
}

usage_dns() {
  cat <<'EOF'
Usage: nixstead [--host <name>] dns sync [options]

Commands:
  sync  Preview or apply registry-driven Pi-hole Local DNS reconciliation

Run `nixstead dns sync help` for command options.
EOF
}

usage_forge() {
  cat <<'EOF'
Usage: nixstead [--host <name>] forge mirror -i <input-file> [options]

Commands:
  mirror  Import GitHub repositories as Forgejo pull mirrors

Run `nixstead forge mirror help` for command options.
EOF
}

while (($# > 0)); do
  case "$1" in
    --host)
      (($# >= 2)) || die "--host requires a value"
      HOST_NAME="$2"
      shift 2
      ;;
    --repo-root)
      (($# >= 2)) || die "--repo-root requires a value"
      REPO_ROOT="$2"
      shift 2
      ;;
    --secrets-dir)
      (($# >= 2)) || die "--secrets-dir requires a value"
      SECRETS_DIR="$2"
      shift 2
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*) die "unknown global option: $1" ;;
    *) break ;;
  esac
done

export NIXSTEAD_REPOSITORY_ROOT="${REPO_ROOT}"
[[ -z "${HOST_NAME}" ]] || export NIXSTEAD_HOST="${HOST_NAME}"
[[ -z "${SECRETS_DIR}" ]] || export NIXSTEAD_SECRETS_DIR="${SECRETS_DIR}"

COMMAND="${1:-}"
[[ -n "${COMMAND}" ]] || {
  usage
  exit 1
}
shift

case "${COMMAND}" in
  setup)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_setup >&2
      exit 1
    }
    shift
    case "${operation}" in
      -h | --help | help) usage_setup ;;
      wizard)
        if leaf_help_requested "$@"; then
          usage_setup_wizard
          exit 0
        fi
        setup_program="${NIXSTEAD_SETUP_PROGRAM:-${REPO_ROOT}/setup.sh}"
        exec "${setup_program}" "$@"
        ;;
      sops)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/configure-sops-host.sh" --help
        fi
        require_host
        exec "${SCRIPT_ROOT}/configure-sops-host.sh" "$@" "${HOST_NAME}"
        ;;
      *) die "unknown setup command: ${operation}" ;;
    esac
    ;;
  check)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_check >&2
      exit 1
    }
    shift
    case "${operation}" in
      -h | --help | help)
        usage_check
        ;;
      preflight)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/healthcheck.sh" --help
        fi
        require_no_args "$@"
        require_host
        run_with_host_and_secrets healthcheck.sh
        ;;
      runtime)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/health-homelab.sh" --help
        fi
        require_no_args "$@"
        require_host
        runtime_status=0
        run_with_host_and_secrets health-homelab.sh || runtime_status=1
        NIXSTEAD_DETAILS_ONLY=true run_with_host_and_secrets dev-healthcheck.sh || runtime_status=1
        exit "${runtime_status}"
        ;;
      secrets)
        check="${1:-}"
        [[ -n "${check}" ]] || {
          usage_check_secrets >&2
          exit 1
        }
        shift
        case "${check}" in
          -h | --help | help) usage_check_secrets ;;
          homepage)
            if leaf_help_requested "$@"; then
              exec "${SCRIPT_ROOT}/check-homepage-secrets.sh" --help
            fi
            require_no_args "$@"
            exec "${SCRIPT_ROOT}/check-homepage-secrets.sh" --strict-local
            ;;
          store)
            if leaf_help_requested "$@"; then
              exec "${SCRIPT_ROOT}/check-secret-store-leaks.sh" --help
            fi
            require_no_args "$@"
            require_host
            run_with_host_and_secrets check-secret-store-leaks.sh
            ;;
          *) die "unknown secret check: ${check}" ;;
        esac
        ;;
      *) die "unknown check: ${operation}" ;;
    esac
    ;;
  credentials)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_credentials >&2
      exit 1
    }
    shift
    case "${operation}" in
      -h | --help | help) usage_credentials ;;
      bootstrap)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/generate-credential-files.sh" --help
        fi
        exec "${SCRIPT_ROOT}/generate-credential-files.sh" "$@"
        ;;
      configure)
        target="${1:-}"
        [[ -n "${target}" ]] || {
          usage_credentials_configure >&2
          exit 1
        }
        shift || true
        case "${target}" in
          -h | --help | help) usage_credentials_configure ;;
          homepage)
            if leaf_help_requested "$@"; then
              exec "${SCRIPT_ROOT}/configure-homepage-integrations.sh" --help
            fi
            require_no_args "$@"
            exec "${SCRIPT_ROOT}/configure-homepage-integrations.sh"
            ;;
          *) die "unknown credential configuration target: ${target}" ;;
        esac
        ;;
      validate)
        target="${1:-}"
        [[ -n "${target}" ]] || {
          usage_credentials_validate >&2
          exit 1
        }
        shift || true
        case "${target}" in
          -h | --help | help) usage_credentials_validate ;;
          homepage)
            if leaf_help_requested "$@"; then
              exec "${SCRIPT_ROOT}/check-homepage-secrets.sh" --help
            fi
            require_no_args "$@"
            exec "${SCRIPT_ROOT}/check-homepage-secrets.sh" --strict-local
            ;;
          *) die "unknown credential validation target: ${target}" ;;
        esac
        ;;
      list | show | sync | rotate)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/service-credentials.sh" --help
        fi
        exec "${SCRIPT_ROOT}/service-credentials.sh" "${operation}" "$@"
        ;;
      *) die "unknown credentials command: ${operation}" ;;
    esac
    ;;
  images)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_images >&2
      exit 1
    }
    shift
    if is_help_token "${operation}"; then
      usage_images
      exit 0
    fi
    if leaf_help_requested "$@"; then
      exec "${SCRIPT_ROOT}/container-images.sh" --help
    fi
    require_host
    case "${operation}" in
      list | diff)
        require_no_args "$@"
        exec "${SCRIPT_ROOT}/container-images.sh" "${operation}" "${HOST_NAME}"
        ;;
      set | reset)
        image_options=()
        while (($# > 0)); do
          case "$1" in
            --dry-run | --allow-downgrade)
              image_options+=("$1")
              shift
              ;;
            --)
              shift
              break
              ;;
            *) break ;;
          esac
        done
        exec "${SCRIPT_ROOT}/container-images.sh" "${operation}" "${image_options[@]}" "${HOST_NAME}" "$@"
        ;;
      *) die "unknown images command: ${operation}" ;;
    esac
    ;;
  backup)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_backup >&2
      exit 1
    }
    shift
    case "${operation}" in
      -h | --help | help) usage_backup ;;
      create)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/backup-service-configs.sh" --help
        fi
        require_no_args "$@"
        exec "${SCRIPT_ROOT}/backup-service-configs.sh"
        ;;
      verify)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/test-service-backup-restore.sh" --help
        fi
        exec "${SCRIPT_ROOT}/test-service-backup-restore.sh" "$@"
        ;;
      restore)
        if leaf_help_requested "$@"; then
          exec "${SCRIPT_ROOT}/restore-service-configs.sh" --help
        fi
        exec "${SCRIPT_ROOT}/restore-service-configs.sh" "$@"
        ;;
      *) die "unknown backup command: ${operation}" ;;
    esac
    ;;
  dns)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_dns >&2
      exit 1
    }
    shift || true
    if is_help_token "${operation}"; then
      usage_dns
      exit 0
    fi
    [[ "${operation}" == sync ]] || die "dns currently supports only sync"
    if leaf_help_requested "$@"; then
      exec "${SCRIPT_ROOT}/sync-pihole-local-dns-from-nginx.sh" --help
    fi
    exec "${SCRIPT_ROOT}/sync-pihole-local-dns-from-nginx.sh" "$@"
    ;;
  forge)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_forge >&2
      exit 1
    }
    shift || true
    if is_help_token "${operation}"; then
      usage_forge
      exit 0
    fi
    [[ "${operation}" == mirror ]] || die "forge currently supports only mirror"
    if leaf_help_requested "$@"; then
      exec "${SCRIPT_ROOT}/mirror-github-to-forgejo.sh" --help
    fi
    exec "${SCRIPT_ROOT}/mirror-github-to-forgejo.sh" "$@"
    ;;
  media)
    operation="${1:-}"
    [[ -n "${operation}" ]] || {
      usage_media >&2
      exit 1
    }
    shift
    if is_help_token "${operation}"; then
      usage_media
      exit 0
    fi
    if leaf_help_requested "$@"; then
      case "${operation}" in
        transcode) exec "${SCRIPT_ROOT}/convert-videos-efficiently.sh" --help ;;
        hardlinks) exec "${SCRIPT_ROOT}/hardlinks.sh" --help ;;
        rom-import) exec "${SCRIPT_ROOT}/copy-batocera-roms-to-romm.sh" --help ;;
        kavita-import) exec "${SCRIPT_ROOT}/prepare-kavita-library.sh" --help ;;
      esac
    fi
    [[ "${MEDIA_ENABLED}" == true ]] || die "media tools are not enabled; set nixstead.tools.media.enable = true"
    case "${operation}" in
      transcode) exec "${SCRIPT_ROOT}/convert-videos-efficiently.sh" "$@" ;;
      hardlinks) exec "${SCRIPT_ROOT}/hardlinks.sh" "$@" ;;
      rom-import) exec "${SCRIPT_ROOT}/copy-batocera-roms-to-romm.sh" "$@" ;;
      kavita-import) exec "${SCRIPT_ROOT}/prepare-kavita-library.sh" "$@" ;;
      *) die "unknown media command: ${operation}" ;;
    esac
    ;;
  -h | --help | help) usage ;;
  *) die "unknown command: ${COMMAND}" ;;
esac
