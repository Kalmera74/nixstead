# AGENTS.md

Guidance for coding agents working in this repository.

## Scope

- This file applies to the entire repository unless a deeper `AGENTS.md` overrides it.
- The repo has a single root guidance file at the moment.

## Permissions

- Never create a Git commit unless the user gives explicit permission in the
  current request.
- Never rebuild, switch, activate, or otherwise apply the NixOS system unless
  the user gives explicit permission in the current request. Read-only checks
  such as evaluation and flake checks are allowed when relevant.

## Repo Layout

- Flake entrypoints:
  - `flake.nix` discovers every `hosts/<target>/default.nix` and exposes it as `nixosConfigurations.<target>`.
  - `flake.nix` exposes the supported reusable surface under `nixosModules` and `templates`; internal paths are not the public API.
  - The target selected by `--flake path:.#<target>` determines the host; the flake does not hardcode a machine.
  - The imported hardware configuration declares `nixpkgs.hostPlatform`, which `nixosSystem` uses as the target architecture.
- Host wiring:
  - `modules/default.nix` is the shared complete import.
  - `hosts/<target>/default.nix` imports its hardware configuration and selected program modules, and may set `nixstead.preset`.
  - Registry-driven presets use `lib.mkDefault` so host configuration can override any preset selection.
  - Hosts declare their own `system.stateVersion`; shared modules must not set it.
  - Repository-local hosts select a service preset and import program modules
    directly from `hosts/<target>/default.nix`; external consumers use the
    exported `nixosModules` surface.
- Module layout:
  - `modules/core/options.nix` defines typed host options, registry-backed option helpers, and `nixstead.serviceRegistry`.
  - `modules/base.nix` and `modules/default.nix` implement the public module API.
  - `modules/services/registry.nix` is the stable aggregate entrypoint for service defaults and integration metadata.
  - `modules/services/registry/*.nix` contains stack-aligned registry fragments plus `standalone.nix`; `registry/lib.nix` contains their pure constructors.
  - `modules/services/presets.nix` renders `nixstead.preset` into overrideable service defaults.
  - `modules/services/services.nix` is the service-module orchestrator.
  - `modules/services/<stack>/*.nix` contains stack wrappers and concrete service modules.
  - `modules/services/homepage/services-registry.nix` generates service cards; surrounding Homepage modules contain layout, static cards, and runtime SOPS placeholders.
  - `modules/services/nginx/registry-proxies.nix` generates reverse-proxy vhosts; `nginx.nix` owns local TLS generation.
  - `modules/system/*.nix` contains core machine, user, network, and locale setup.
  - `modules/hardware/*.nix` contains hardware-specific configuration.
  - `modules/programs/*.nix` contains independent program groups selected directly by each host; there is no default aggregate import.
- Scripts:
  - `setup.sh` reads service choices, option paths, presets, labels, and secret requirements from the registry.
  - `scripts/` contains utility scripts.

## Service Conventions

- Keep service changes in `modules/services/*` unless the task explicitly needs a different layer.
- Ordinary services use an attrset with an `.enable` field plus endpoint/path settings.
- Stack groups use an attrset with `.enable` plus child service options.
- Parent `enable = true` should only set child toggles to `true` by default with `lib.mkDefault`.
- Child services must remain independently disable-able, even when the parent is enabled.
- Service modules, nginx vhosts, and Homepage cards should all key off the child toggle, not the parent flag.
- Avoid renaming existing options or moving them between groups unless explicitly requested.
- Add shared names, defaults, setup metadata, proxy/card metadata, health units, secret requirements, firewall policy, DNS participation, and backup policy to the matching fragment under `modules/services/registry/`.
- Use `serviceOptionFromRegistry` for ordinary service options and keep implementation-specific behavior in the service module.
- Put a service in an existing coherent stack whenever possible. Create a new
  stack only when it owns at least two related services; otherwise keep the
  module at `modules/services/<service>.nix` under `nixstead.services.<service>`.

## Current Stack Shapes

- ARR stack:
  - Parent option: `nixstead.services.arr.enable`
  - Child toggles: `sonarr`, `radarr`, `lidarr`, `readarr`, `bazarr`, `prowlarr`, `qbittorrent`, `swaparr`, `sabnzbd`, `shelfmark`
  - Defaults are set in `modules/services/arr/arr.nix`
- Media stack:
  - Parent option: `nixstead.services.media.enable`
  - Child toggles: `jellyfin`, `seerr`, `tdarr`, `komga`, `kavita`, `audiobookshelf`, `kiwix`, `immich`, `romm`, `tubearchivist`
  - Defaults are set in `modules/services/media/media.nix`
- Dev stack:
  - Parent option: `nixstead.services.dev.enable`
  - Child toggles: `grafana`, `prometheus`, `loki`, `redis`, `rabbitmq`, `postgresql`, `mongodb`, `forgejo`, `gitea`, `pgadmin`, `seaweedfs`, `uptimekuma`
  - Defaults are set in `modules/services/dev/dev.nix`
- Local AI stack:
  - Parent option: `nixstead.services.localai.enable`
  - Child toggles: `ollama`, `llamacpp`, `stablediffusioncpp`, `openwebui`
  - Defaults are set in `modules/services/localai/localai.nix`
- Productivity stack:
  - Parent option: `nixstead.services.productivity.enable`
  - Child toggles: `paperless`, `nextcloud`, `n8n`, `stirlingpdf`, `seafile`, `wallabag`, `linkwarden`, `snapotter`
  - Defaults are set in `modules/services/productivity/productivity.nix`
- Standalone services:
  - Vaultwarden uses `nixstead.services.vaultwarden` in `modules/services/vaultwarden.nix`.
  - Home Assistant uses `nixstead.services.homeassistant` in `modules/services/homeassistant.nix`.
  - Tailscale uses `nixstead.services.tailscale` in `modules/services/tailscale.nix`.
  - WireGuard uses `nixstead.services.wireguard` in `modules/services/wireguard.nix`; application adapters such as ARR select its namespaces and own their application-specific listeners.

## Homepage

- Homepage service cards are generated by `modules/services/homepage/services-registry.nix` from registry metadata.
- Section layout is controlled in `modules/services/homepage/settings.nix`.
- Keep card keys, URLs, and widgets aligned with registry settings and existing Homepage conventions.
- Keep Homepage registry entries keyed to the child toggle so disabling a child removes only that card.
- Add Homepage secret names to registry widget metadata and
  `secrets/secrets.example.yaml`; `homepage.nix` turns them into runtime
  `HOMEPAGE_VAR_*` placeholders and an sops-nix environment template.

## Nginx

- `modules/services/nginx/nginx.nix` enables nginx and generates the local CA/certs.
- `modules/services/nginx/lib.nix` provides reusable TLS helpers.
- `modules/services/nginx/registry-proxies.nix` generates service vhosts from the central registry.
- Keep vhosts tied to the child toggle that controls the service itself.
- Use resolved registry settings as the source of truth for proxy targets.

## Secrets

- Keep plaintext values out of Nix evaluation, derivations, unit scripts, and
  ordinary container `environment` attributes.
- Declare encrypted keys with `sops.secrets` and pass only runtime paths or
  `sops.placeholder` values to consumers.
- Prefer native file options; use root- or service-readable SOPS templates for
  `EnvironmentFile` consumers.
- Add schema-only placeholders to `secrets/secrets.example.yaml`.
- Preserve `NIXSTEAD_SECRETS_DIR` as an encrypted `<host>.yaml` directory
  override and `NIXCONFIG_SECRETS_DIR` as its deprecated compatibility alias;
  neither variable may restore plaintext Nix imports.

## Scripts

- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Add a `usage()` function for scripts that take arguments.
- Validate required commands with `command -v`.
- Quote variables and paths; avoid unsafe globbing.
- Prefer explicit opt-in flags for destructive actions.
- Keep repo scripts consistent with the current helper style in `scripts/`.

## Validation

Prefer validating the affected scope first:

1. Shell scripts:
   - `bash -n scripts/<script>.sh`
2. Nix evaluation:
   - `nix flake check path:.`
3. Host-level changes:
   - Use a pure rebuild for repository host files, or the documented impure
     `NIXSTEAD_SECRETS_DIR` override for external encrypted files. The legacy
     `NIXCONFIG_SECRETS_DIR` alias must remain supported.

## Things To Avoid

- Do not add a new top-level structure when an existing service category already fits.
- Do not add heavy dependencies without a clear request.
- Do not commit plaintext secrets, age identities, SSH private keys, or
  decrypted exports.
- Do not remove the encrypted `NIXSTEAD_SECRETS_DIR` override or its deprecated
  `NIXCONFIG_SECRETS_DIR` compatibility alias.

## Media operations

- Seerr is the sole supported request-service name; its native state revision is 1.
- Storage and API reconciliation are opt-in; stack selection must not create a media hierarchy or mutate application APIs.
- Preserve ownership-journal semantics and unowned application fields in adapters.
- Keep API, metrics, state and setup metadata in the service registry.
- Document new runtime coverage precisely in `docs/support-matrix.md`; regenerate `docs/generated/services.md` after registry changes.
- Keep broad formatter changes separate from behavioral changes.
