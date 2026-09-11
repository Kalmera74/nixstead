# Service guides

These guides describe how each supported service is implemented by Nixstead,
which options the repository owns, where initial credentials come from, and
what to inspect after activation. They document this repository rather than
every upstream application setting.

Registry-backed services normally expose `enable`, `domain`, `ip`, and `port`
at the option path shown in their guide. `domain` is derived from
`nixstead.host.network.baseDomain` unless explicitly overridden. Services with
repository-managed storage also expose the documented `paths` options. Changing
a path does not migrate existing data.

Credentials fall into three groups:

- SOPS credentials are generated with
  `nixstead --host <host> credentials bootstrap <domain>` and decrypted below
  `/run/secrets` only on the host.
- Runtime credentials are generated directly into a service-owned state
  directory and can be read as root with the command in that service's guide.
- First-run credentials are created through the application's onboarding page;
  Nixstead does not know or store the resulting password.

After changing a service, validate with `nix flake check path:.` and activate
the intended host separately. See [Secrets and credentials](../secrets.md),
[Networking](../networking.md), and [Operations](../operations.md) for shared
procedures.

## ARR

- [Sonarr](sonarr.md)
- [Radarr](radarr.md)
- [Lidarr](lidarr.md)
- [Readarr](readarr.md)
- [Bazarr](bazarr.md)
- [Prowlarr](prowlarr.md)
- [qBittorrent](qbittorrent.md)
- [Swaparr](swaparr.md)
- [SABnzbd](sabnzbd.md)
- [Shelfmark](shelfmark.md)
- [qBittorrent VPN confinement](qbittorrent-vpn.md)
- [ARR ntfy notifications](ntfy-integrations.md)

Shared contracts: [media operations](../media-operations.md),
[verification matrix](../support-matrix.md), and [generated catalog](../generated/services.md).

## Media

- [Jellyfin](jellyfin.md)
- [Seerr](seerr.md)
- [Tdarr server and node](tdarr.md)
- [Komga](komga.md)
- [Kavita](kavita.md)
- [Audiobookshelf](audiobookshelf.md)
- [Kiwix](kiwix.md)
- [Immich](immich.md)
- [RomM](romm.md)
- [TubeArchivist](tubearchivist.md)

## Development and monitoring

- [Grafana](grafana.md)
- [Prometheus](prometheus.md)
- [Loki](loki.md)
- [Redis](redis.md)
- [RabbitMQ](rabbitmq.md)
- [PostgreSQL](postgresql.md)
- [MongoDB](mongodb.md)
- [Forgejo](forgejo.md)
- [Gitea](gitea.md)
- [pgAdmin](pgadmin.md)
- [SeaweedFS](seaweedfs.md)
- [Uptime Kuma](uptime-kuma.md)
- [ntfy](ntfy.md)
- [Scrutiny](scrutiny.md)

## Local AI

- [Ollama](ollama.md)
- [llama.cpp](llama-cpp.md)
- [stable-diffusion.cpp](stable-diffusion-cpp.md)
- [Open WebUI](open-webui.md)

## Productivity

- [Paperless-ngx](paperless-ngx.md)
- [Nextcloud](nextcloud.md)
- [n8n](n8n.md)
- [Stirling PDF](stirling-pdf.md)
- [Seafile](seafile.md)
- [Wallabag](wallabag.md)
- [Linkwarden](linkwarden.md)
- [SnapOtter](snapotter.md)
- [Mealie](mealie.md)
- [Actual Budget](actual-budget.md)
- [Miniflux](miniflux.md)
- [SearXNG](searxng.md)

## Standalone and platform

- [Vaultwarden](vaultwarden.md)
- [Home Assistant](home-assistant.md)
- [authentik](authentik.md)
- [Syncthing](syncthing.md)
- [Nginx](nginx.md)
- [Homepage](homepage.md)
- [Tailscale](tailscale.md)
- [WireGuard host tunnels and application namespaces](wireguard.md)

## Storage and external integrations

- [CIFS client](cifs.md)
- [mergerfs](mergerfs.md)
- [SnapRAID](snapraid.md)
- [Samba](samba.md)
- [Pi-hole integration](pihole.md)
- [Proxmox integration](proxmox.md)
- [TrueNAS integration](truenas.md)
