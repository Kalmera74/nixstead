# Presets

Presets are named, registry-driven starting points for service selection. They
replace the former collection of profile files and avoid duplicating service
lists between Nix modules and the setup wizard.

## Selecting a preset

```nix
nixstead.preset = "media-starter";
```

Valid values are:

- `none`
- `minimal`
- `media-starter` (recommended streaming start)
- `media-server`
- `development`
- `full`

`none` is the default.

## Behavior

Each preset-controlled registry entry declares membership:

```nix
setup = setup "arr" 20 ["media-server" "full"];
```

The preset renderer finds matching entries and applies:

```nix
lib.mkDefault true
```

to the entry's setup or enable path. This priority is intentional: explicit
host values always win.

```nix
{
  nixstead.preset = "full";
  nixstead.services.productivity.nextcloud.enable = false;
}
```

## Preset summary

### `none`

No service is enabled by the preset. Use it for a completely explicit host or
for a generated custom selection.

### `minimal`

Enables Tailscale only. It is intended as a safe remote-administration starting
point with no application or storage stack.

### `media-starter` (recommended)

Selects only Jellyfin, Seerr, Sonarr, Radarr, Prowlarr, qBittorrent, Homepage and
Nginx. Parent stack switches stay off, and every child can be disabled separately.
Tailscale, extra reading/photo/ROM apps, transcoding workers, monitoring and
program groups are opt-in. Start here and enable one additional service at a time:

```nix
nixstead.preset = "media-starter";
nixstead.services.media.audiobookshelf.enable = true;
```

A starting planning budget is 4 CPU cores and 8 GiB RAM, plus persistent metadata,
media/download capacity and a separate backup target. This is guidance, not a
measured minimum; concurrent transcoding may need a GPU or more CPU. Application
state and media need separate capacity planning. Setup shows each service's
coverage and requirements; [the matrix](support-matrix.md) distinguishes API,
startup and restore evidence. The starter does not claim a tested full request,
download and playback pipeline.

## `media-server` (extended catalog)

Enables:

- ARR: Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, qBittorrent, Swaparr;
- media: Jellyfin, Seerr, Tdarr server/node, Komga, Kavita,
  Audiobookshelf, Kiwix, Immich, RomM, and TubeArchivist;
- platform: Nginx, Homepage, and Tailscale; and
- the ARR and media parent stack indicators.

Hosts commonly disable media applications they do not use.

### `development`

Enables:

- Grafana, Prometheus, and Loki;
- Redis, RabbitMQ, PostgreSQL, and MongoDB;
- Forgejo, pgAdmin, SeaweedFS, Uptime Kuma, and ntfy; and
- Nginx, Homepage, and Tailscale.

Gitea is deliberately not a preset member because it is an alternative to
Forgejo. The preset enables selected children directly and leaves
`nixstead.services.dev.enable` false; enabling the parent would also select Gitea.

### `full` (advanced/demo)

This is a catalog demonstration and advanced migration starting point, not the
recommended choice for a new host. Review every enabled service, storage
requirement, credential domain, and backup policy before using it.

Enables the media-server and development selections plus:

- Ollama, llama.cpp, stable-diffusion.cpp, and Open WebUI;
- Paperless-ngx, Nextcloud, n8n, Stirling PDF, Seafile, Wallabag, Linkwarden,
  SnapOtter, Mealie, Actual Budget, Miniflux, and SearXNG; and
- standalone Vaultwarden, Home Assistant, Syncthing, and Scrutiny.

It also enables the ARR, media, local-AI, and productivity parent stack
indicators. Gitea remains excluded in favor of Forgejo.

## What presets never select

Machine-specific features remain explicit:

- CIFS shares;
- local NAS disks, mergerfs, SnapRAID, and Samba;
- Pi-hole integration;
- Proxmox integration; and
- TrueNAS integration.

These require host addresses, share definitions, or physical device choices.

## Parent stacks versus presets

A parent stack is a broad mechanical “enable every child by default” control:

```nix
nixstead.services.dev.enable = true;
```

A preset is a curated cross-stack role. Prefer a preset for a complete host
starting point and a parent toggle when intentionally enabling an entire single
stack.

## Compatibility module names

The public API retains:

- `nixosModules.profile-minimal`
- `nixosModules.profile-media-server`
- `nixosModules.profile-development`
- `nixosModules.profile-full`

They are wrappers that import `nixosModules.default` and assign `nixstead.preset`.
New consumers should use the default module plus `nixstead.preset` directly.

## Adding or changing preset membership

Edit the relevant service's `setup.presets` in its stack fragment under
`modules/services/registry/`. Do not add a parallel service list to `presets.nix`
or `setup.sh`.

The flake API check compares registry membership to the evaluated compatibility
wrappers and verifies that explicit overrides still win:

```bash
nix flake check path:.
```
