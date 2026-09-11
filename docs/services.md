# Services

The complete module exposes a broad service catalog while leaving selection to
the host or its preset. Service-specific modules own packages, containers,
users, directories, and lifecycle behavior. The registry owns repeated
integration metadata. For first-login instructions, exact option paths, storage,
and unit-level troubleshooting, use the [per-service guides](services/README.md).

## Catalog

| Category | Services |
| --- | --- |
| ARR | Sonarr, Radarr, Lidarr, Readarr, Bazarr, Prowlarr, qBittorrent, Swaparr, optional SABnzbd/Shelfmark |
| Media | Jellyfin, Seerr, Tdarr server/node, Komga, Kavita, Audiobookshelf, Kiwix, Immich, RomM, TubeArchivist |
| Development | Grafana, Prometheus, Loki, Redis, RabbitMQ, PostgreSQL, MongoDB, Forgejo, Gitea, pgAdmin, SeaweedFS, Uptime Kuma, ntfy |
| Local AI | Ollama, llama.cpp, stable-diffusion.cpp, Open WebUI |
| Productivity | Paperless-ngx, Nextcloud, n8n, Stirling PDF, Seafile, Wallabag, Linkwarden, SnapOtter, Mealie, Actual Budget, Miniflux, SearXNG |
| Standalone | Vaultwarden, Home Assistant, authentik, Syncthing, Scrutiny |
| Platform | Nginx, Homepage, Tailscale, optional WireGuard host tunnels and application namespaces |
| Storage | CIFS client, mergerfs, SnapRAID, Samba |
| External integration | Pi-hole, Proxmox, TrueNAS |

## Default endpoint and preset reference

These domains assume the default `nixstead.host.network.baseDomain = "home.arpa"`.
Hosts can change that base once or override an individual endpoint. An em dash
means the entry does not expose a standard HTTP-style endpoint or has no preset
membership.

| Registry ID | Service | Default domain | Default port | Presets |
| --- | --- | --- | ---: | --- |
| `actualbudget` | Actual Budget | `budget.home.arpa` | 8189 | full |
| `audiobookshelf` | Audiobookshelf | `audiobookshelf.home.arpa` | 13378 | media-server, full |
| `authentik` | authentik | `auth.home.arpa` | 9000 | — |
| `bazarr` | Bazarr | `bazarr.home.arpa` | 6767 | media-server, full |
| `cifs` | CIFS | — | — | — |
| `forgejo` | Forgejo | `forgejo.home.arpa` | 3000 | development, full |
| `gitea` | Gitea | `gitea.home.arpa` | 3002 | — |
| `grafana` | Grafana | `grafana.home.arpa` | 3001 | development, full |
| `homeassistant` | Home Assistant | `homeassistant.home.arpa` | 8123 | full |
| `homepage` | Homepage | `home.home.arpa` | 2525 | media-starter, media-server, development, full |
| `immich` | Immich | `immich.home.arpa` | 2283 | media-server, full |
| `jellyfin` | Jellyfin | `watch.home.arpa` | 8096 | media-starter, media-server, full |
| `seerr` | Seerr | `want.home.arpa` | 5055 | media-starter, media-server, full |
| `kavita` | Kavita | `kavita.home.arpa` | 5000 | media-server, full |
| `kiwix` | Kiwix | `wiki.home.arpa` | 9090 | media-server, full |
| `komga` | Komga | `komga.home.arpa` | 25600 | media-server, full |
| `lidarr` | Lidarr | `lidarr.home.arpa` | 8686 | media-server, full |
| `linkwarden` | Linkwarden | `linkwarden.home.arpa` | 8186 | full |
| `llamacpp` | llama.cpp | `llama.home.arpa` | 8084 | full |
| `loki` | Loki | `loki.home.arpa` | 3100 | development, full |
| `mealie` | Mealie | `mealie.home.arpa` | 8188 | full |
| `miniflux` | Miniflux | `reader.home.arpa` | 8190 | full |
| `mongodb` | MongoDB | `mongo.home.arpa` | 27017 | development, full |
| `n8n` | n8n | `n8n.home.arpa` | 5678 | full |
| `nas` | NAS | — | — | — |
| `nextcloud` | Nextcloud | `nextcloud.home.arpa` | 8083 | full |
| `nginx` | Nginx | — | — | media-starter, media-server, development, full |
| `ntfy` | ntfy | `ntfy.home.arpa` | 2586 | development, full |
| `ollama` | Ollama | `ollama.home.arpa` | 11434 | full |
| `openwebui` | Open WebUI | `ai.home.arpa` | 8081 | full |
| `paperless` | Paperless-ngx | `paperless.home.arpa` | 28981 | full |
| `pgadmin` | pgAdmin | `pgadmin.home.arpa` | 5050 | development, full |
| `pihole` | Pi-hole | `pihole.home.arpa` | 80 | — |
| `postgresql` | PostgreSQL | `postgres.home.arpa` | 5432 | development, full |
| `prometheus` | Prometheus | `prometheus.home.arpa` | 9091 | development, full |
| `prowlarr` | Prowlarr | `prowlarr.home.arpa` | 9696 | media-starter, media-server, full |
| `proxmox` | Proxmox | `proxmox.home.arpa` | 8006 | — |
| `qbittorrent` | qBittorrent | `bit.home.arpa` | 8080 | media-starter, media-server, full |
| `rabbitmq` | RabbitMQ | `rabbitmq.home.arpa` | 5672 | development, full |
| `radarr` | Radarr | `radarr.home.arpa` | 7878 | media-starter, media-server, full |
| `readarr` | Readarr (retired) | `readarr.home.arpa` | 8787 | — |
| `redis` | Redis | `redis.home.arpa` | 6379 | development, full |
| `romm` | RomM | `romm.home.arpa` | 8182 | media-server, full |
| `samba` | Samba | — | — | — |
| `scrutiny` | Scrutiny | `scrutiny.home.arpa` | 8192 | full |
| `seafile` | Seafile | `seafile.home.arpa` | 8184 | full |
| `seaweedfs` | SeaweedFS | `seaweed.home.arpa` | 8888 | development, full |
| `searxng` | SearXNG | `search.home.arpa` | 8191 | full |
| `snapotter` | SnapOtter | `images.home.arpa` | 8187 | full |
| `sonarr` | Sonarr | `sonarr.home.arpa` | 8989 | media-starter, media-server, full |
| `stablediffusioncpp` | stable-diffusion.cpp | `stable.home.arpa` | 1234 | full |
| `stirlingpdf` | Stirling PDF | `pdf.home.arpa` | 8082 | full |
| `swaparr` | Swaparr | — | — | media-server, full |
| `syncthing` | Syncthing | `syncthing.home.arpa` | 8384 | full |
| `tailscale` | Tailscale | — | — | minimal, media-server, development, full |
| `wireguard` | WireGuard | — | — | — |
| `tdarr` | Tdarr | `tdarr.home.arpa` | 8265 | media-server, full |
| `tdarr-node` | Tdarr node | — | — | — |
| `truenas` | TrueNAS | `nas.home.arpa` | 80 | — |
| `tubearchivist` | TubeArchivist | `tube.home.arpa` | 8183 | media-server, full |
| `uptimekuma` | Uptime Kuma | `uptimekuma.home.arpa` | 3010 | development, full |
| `vaultwarden` | Vaultwarden | `vaultwarden.home.arpa` | 8222 | full |
| `wallabag` | Wallabag | `wallabag.home.arpa` | 8185 | full |

## Enabling services

Enable a child directly:

```nix
nixstead.services.media.jellyfin.enable = true;
nixstead.services.vaultwarden.enable = true;
nixstead.services.homeassistant.enable = true;
nixstead.services.authentik.enable = true;
nixstead.services.syncthing.enable = true;
nixstead.services.scrutiny.enable = true;
```

Enable a parent stack and exclude children:

```nix
nixstead.services.productivity = {
  enable = true;
  nextcloud.enable = false;
  seafile.enable = false;
  snapotter.enable = false;
};
```

Or select a preset and override it:

```nix
nixstead.preset = "media-server";
nixstead.services.media.kiwix.enable = false;
```

## Endpoint overrides

Registry-backed ordinary services normally support `domain`, `ip`, and `port`.
Only services that manage custom storage add a typed `paths` submodule:

```nix
# Changes derived defaults such as radarr.home.arpa to radarr.lab.example.com.
nixstead.host.network.baseDomain = "lab.example.com";
```

An explicit service domain takes precedence over that derived default:

```nix
nixstead.services.media.jellyfin = {
  enable = true;
  domain = "watch.home.arpa";
  ip = "192.168.1.20";
  port = 8096;
};
```

The implementation and registry renderers consume the resolved values, so a
port change reaches the application listener as well as generated proxy,
dashboard, firewall, and health metadata. Base-domain and per-service domain
changes also reach DNS and other domain-aware integrations where applicable.

Numbers on the container side of OCI mappings remain fixed image contracts;
the configurable host-side port always comes from the service option.

Path overrides select the application's real state location but do not migrate
existing files. Stop the service and move its state deliberately before
changing a path on an installed host. All supported host-facing overrides live
under the service's `nixstead.services` namespace as named, typed runtime paths. The
implementation translates them to native NixOS or container settings.

Enabled applications may not claim the same TCP port or the same UDP port on a
host. Evaluation reports both service IDs and option sources for a collision.
External integrations such as Pi-hole and Proxmox are excluded because their
listeners run on another machine.

## ARR stack

```nix
nixstead.services.arr = {
  enable = true;
  lidarr.enable = false;
  readarr.enable = false;

  qbittorrent.paths = {
    savePath = "/mnt/media/data/torrents/";
    tempPath = "/mnt/media/data/torrents/temp/";
  };
};
```

Swaparr follows the same child-service shape as the other ARR services:

```nix
nixstead.services.arr.swaparr.enable = false;
```

## Media stack and Tdarr

Tdarr supports separate server and local-node choices:

```nix
nixstead.services.media.tdarr = {
  enable = true;
  server = true;
  node = true;
  port = 8265;       # Web UI
  serverPort = 8266; # Node/server API
  paths = {
    cacheDir = "/mnt/appdata/selfhosted/tdarr/cache";
    dataDir = "/mnt/appdata/selfhosted/tdarr";
    mediaDir = "/mnt/media";
  };
};
```

The registry treats the server as the proxy/dashboard endpoint and the node as
a separate health-check participant. Both Tdarr host ports participate in the
selected exposure policy. Typed `paths.dataDir` overrides the native state
location. `paths.cacheDir` and `paths.mediaDir` make the shared transcode cache
and host media storage writable to the server and local node. Leaving any path
unset preserves the implementation default.

Kavita exposes `nixstead.services.media.kavita.paths.dataDir` and models its
token-signing key separately through `tokenKeyFile`. Both inherit their native
defaults when unset.

Audiobookshelf and Prometheus expose optional typed paths in their own
`nixstead.services` submodules while retaining the native systemd-managed defaults
when those overrides are unset.

## Development stack

Forgejo is the preset-selected Git forge. Gitea remains available as an
alternative:

```nix
nixstead.services.dev = {
  forgejo.enable = false;
  gitea.enable = true;
};
```

Forgejo exposes `nixstead.services.dev.forgejo.paths.stateDir` and
`nixstead.services.dev.forgejo.paths.repositoryDir`. Its module translates those
values to the native Forgejo options, keeping the implementation detail out of
host configuration.

SeaweedFS similarly exposes its filer endpoint as `port` and its internal
master endpoint as `masterPort`; both are passed to the service command rather
than duplicated as module literals. Its typed `paths.dataDir` is the only
storage root; master, volume, and filer subdirectories are derived from it.

ntfy starts with deny-by-default topic access. The module generates an `admin`
account at first start; read its password with:

```bash
sudo cat /var/lib/ntfy-sh/admin-password
```

Several development services share the `devdb` secret domain. See
[Secrets](secrets.md) before enabling the stack.

## First-login credentials

Miniflux and Syncthing generate bootstrap passwords on first start without
placing them in the Nix store:

```bash
sudo sed -n 's/^ADMIN_PASSWORD=//p' /var/lib/miniflux/admin.env
sudo cat /var/lib/syncthing/.config/syncthing/gui-password
```

Both use `admin` as the initial username. Actual Budget creates its password
through the web interface. Mealie retains its upstream first-login account, so
change that password immediately after signing in.

## Local AI dependencies

stable-diffusion.cpp serves the first-party `sdcpp-webui` image and video
frontend from the same endpoint as its native, OpenAI-compatible, and Stable
Diffusion WebUI APIs.
The default full checkpoint location is
`/var/lib/stable-diffusion-cpp/models/model.safetensors`; the systemd unit waits
until that file exists. Override it for an existing model library:

```nix
nixstead.services.localai.stablediffusioncpp = {
  enable = true;
  paths.modelFile = "/srv/models/stable-diffusion/sd-v1-5.safetensors";
  settings."vae-tiling" = true;
};
```

The frontend enables video when the server reports that the loaded pipeline
supports it. For SD 1.5 checkpoints, add an AnimateDiff motion module:

```nix
nixstead.services.localai.stablediffusioncpp.paths.modelFiles."motion-module" =
  "/srv/models/animatediff/mm_sd_v15_v2.ckpt";
```

For a native video pipeline such as Wan, set `paths.modelFile = null` and use
the mount-aware `paths.modelFiles` map for its standalone diffusion model, VAE,
and text encoder:

```nix
nixstead.services.localai.stablediffusioncpp.paths = {
  modelFile = null;
  modelFiles = {
    "diffusion-model" = "/srv/models/wan/wan2.1-t2v-1.3b.safetensors";
    vae = "/srv/models/wan/wan_2.1_vae.safetensors";
    t5xxl = "/srv/models/wan/umt5-xxl-encoder-Q8_0.gguf";
  };
};
```

Each attribute name is passed as an `sd-server` option, allowing any model
component supported by the selected package. General runtime flags remain in
`settings`. The module selects CPU, CUDA, or ROCm builds from
`nixstead.host.hardware.gpu.acceleration`.

Open WebUI uses the locally enabled Ollama service by default. If Ollama runs on
another machine, disable the local child and provide its endpoint explicitly:

```nix
nixstead.services.localai = {
  ollama.enable = false;
  openwebui = {
    enable = true;
    ollamaUrl = "http://ollama.internal:11434";
  };
};
```

Enabling Open WebUI without either source is rejected during evaluation.

## Stack placement and standalone services

Services live in the stack that owns their role:

```nix
nixstead.services = {
  media.immich.enable = true;
  media.romm.enable = true;
  dev.uptimekuma.enable = true;
  productivity.linkwarden.enable = true;
  productivity.snapotter.enable = true;
  productivity.mealie.enable = true;
  productivity.actualbudget.enable = true;
  productivity.miniflux.enable = true;
  productivity.searxng.enable = true;
  vaultwarden.enable = true;
  homeassistant.enable = true;
  authentik.enable = true;
  syncthing.enable = true;
  scrutiny.enable = true;
};
```

## authentik

authentik runs as separate server and worker units backed by the local
PostgreSQL service. An idempotent setup unit creates its role and database from
the pristine `template0`, independently of NixOS's shared database-setup list.
Its signing key is read from SOPS at runtime, and nginx proxies the server's
HTTP listener with WebSocket support.

Generate the encrypted signing key before enabling the service:

```bash
nixstead --host <host> credentials bootstrap authentik
```

Then enable it directly. The remaining listener ports are loopback-only and
can be changed when the defaults conflict with another local service:

```nix
nixstead.services.authentik = {
  enable = true;
  domain = "auth.home.arpa";
  port = 9000;
  workerPort = 9001;
  metricsPort = 9300;
  workerMetricsPort = 9301;
  httpsPort = 9443;
  paths.dataDir = "/var/lib/authentik";
};
```

Vaultwarden, Home Assistant, authentik, Syncthing, and Scrutiny remain
standalone because they do not form a coherent multi-service stack with the
existing categories.

## External integrations

Pi-hole, Proxmox, and TrueNAS options represent systems that already exist
elsewhere. Enabling one creates the selected Nginx/Homepage/DNS integration; it
does not install that product locally.

```nix
nixstead.host.network.proxmox = "192.168.1.10";
nixstead.services.proxmox.enable = true;
```

## Storage services

CIFS and NAS are intentionally excluded from presets. They require explicit
machine-specific configuration. See [Storage and backups](storage-backups.md).

## Integration expectations

Enabling a service may produce several effects according to its registry entry:

- start a NixOS service or container;
- render declared ports according to the host's service exposure policy;
- create an Nginx TLS virtual host when Nginx is enabled;
- add a Homepage card when Homepage is enabled;
- participate in health checks;
- publish a Pi-hole DNS candidate;
- require one or more secret domains; and
- participate in service-configuration backups.

An integration is generated only when both its controlling platform service and
the target service are enabled where relevant.

## Discovering current values

List resolved service state:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.services
```

Inspect one service's complete resolved registry entry:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.serviceRegistry.jellyfin
```

The latter shows the final enabled state, endpoint settings, and all integration
metadata used by scripts and renderers.

## Operational relationships

See [media operations](media-operations.md) for the storage and credential contracts,
opt-in reconciliation and monitoring. The [generated registry catalog](generated/services.md)
is checked for drift; the [support matrix](support-matrix.md) records actual runtime coverage.
