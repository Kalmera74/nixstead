# Homepage dashboard

This directory owns Homepage presentation and service-card rendering.

- `homepage.nix` enables the NixOS service and combines all card sources.
- `services-registry.nix` renders cards/widgets for enabled registry services.
- `services-network.nix` contains host infrastructure cards.
- `settings.nix` controls dashboard layout and appearance.
- `shortcuts.nix` renders host-defined shortcut entries.

```nix
nixstead.services.homepage = {
  enable = true;
  domain = "home.home.arpa";
  port = 2525;
};
```

## Host-defined shortcuts

Each host can populate the shared Shortcuts section through its own
configuration. Shortcut order follows the list order:

```nix
nixstead.services.homepage.shortcuts = [
  {
    name = "NixOS Search";
    href = "https://search.nixos.org/packages";
    icon = "nixos.png";
    description = "Packages";
  }
];
```

`name` and `href` are required. A relative `.png` icon such as `nixos.png` is
resolved against the shared dashboard-icons catalog; direct URLs and Homepage
icon names pass through unchanged. `icon` defaults to `mdi-web`, and
`description` defaults to an empty string. When the list is empty, the renderer
does not emit a Shortcuts service group.

Widget credentials come from canonical service entries or the encrypted `homepage` branch and are exposed
to Homepage as runtime `HOMEPAGE_VAR_*` values. Add ordinary service cards
through registry metadata. The Homepage module validates host shortcuts and
renders them into the shared Shortcuts section.

## Homepage widget credentials

Nixstead keeps widget metadata in the central service registry even when a
service is disabled. A widget is rendered only when both Homepage and its
service are enabled.

Managed media widgets share canonical service entries such as `sonarr/apiKey`.
Other widget credentials belong below `homepage` in the encrypted host document:

```text
secrets/<configurationName>.yaml
```

The values reach Homepage only at runtime through `HOMEPAGE_VAR_*`
placeholders. Never put a real token, password, or API key in a Nix module, the
plaintext example schema, or a command-line argument.

### Complete the post-install branch

First activation creates the `homepage` branch with empty placeholders because
application-issued API keys do not exist yet. After the enabled applications
have started and their initial accounts are configured, run:

```bash
nixstead --host <host> credentials configure homepage
```

The helper prompts for unmanaged widget credentials and updates the encrypted
branch; rebuild to deploy these unmanaged values. Supported ARR, Seerr and
qBittorrent credentials are enrolled automatically before startup. Homepage
shares these canonical SOPS values with other consumers. Encrypted edits are
refreshed automatically, restarting Homepage when its credentials change. See
[credential operations](../../../docs/media-operations.md#canonical-sops-credentials).

qBittorrent's runtime hashing follows the application's
[PBKDF2-SHA512 implementation](https://github.com/qbittorrent/qBittorrent/blob/master/src/base/utils/password.cpp):
a random 16-byte salt, 100,000 iterations, and the `@ByteArray(salt:digest)`
configuration representation. Operators never need to calculate or paste the
hash manually.

For an existing `homepage` branch, edit it directly:

```bash
sops secrets/<host>.yaml
```

Do not use `--force` merely to add one key: it replaces the complete encrypted
branch. Check key-name coverage without printing secret values:

```bash
nixstead --host <host> credentials validate homepage
```

The check verifies key names, not whether values are correct or non-empty.

### API keys and tokens

| Service | SOPS key (under `homepage` unless qualified) | How to obtain it |
| --- | --- | --- |
| Radarr | `radarr/apiKey` | Enrolled and delivered automatically from the canonical SOPS entry. |
| Sonarr | `sonarr/apiKey` | Enrolled and delivered automatically from the canonical SOPS entry. |
| Lidarr | `lidarr/apiKey` | Enrolled and delivered automatically from the canonical SOPS entry. |
| Readarr | `readarrApiKey` | Open **Settings > General** and copy the API key. See the [Homepage Readarr widget guide](https://gethomepage.dev/widgets/services/readarr/). |
| Bazarr | `bazarr/apiKey` | Enrolled and delivered automatically from the canonical SOPS entry. |
| Prowlarr | `prowlarr/apiKey` | Enrolled and delivered automatically from the canonical SOPS entry. |
| Jellyfin | `jellyfinApiKey` | As an administrator, open **Dashboard > Advanced > API Keys**, add a key for Homepage, and copy it. See the [Homepage Jellyfin widget guide](https://gethomepage.dev/widgets/services/jellyfin/). |
| Seerr | `seerr/apiKey` | Enrolled and delivered automatically from the canonical SOPS entry. |
| Audiobookshelf | `audiobookshelfApiKey` | Sign in as an administrator, open **Config > Users**, select the account Homepage should use, and copy its API token. A dedicated account is preferable. See the [Homepage Audiobookshelf widget guide](https://gethomepage.dev/widgets/services/audiobookshelf/). |
| Kavita | `kavitaApiKey` | Sign in with an admin-role account, open **User Settings > 3rd Party Clients**, and create or copy an Auth Key. The key acts as that user, so treat it like a password. See the [Kavita Auth Key guide](https://wiki.kavitareader.com/guides/user-settings/3rdpartycilents/) and [Homepage Kavita widget guide](https://gethomepage.dev/widgets/services/kavita/). |
| Immich | `immichApiKey` | Open **Account Settings > API Keys**, create a key for Homepage, and grant `server.statistics`. The widget is configured for Immich's version-2 API. See the [Homepage Immich widget guide](https://gethomepage.dev/widgets/services/immich/). |
| TubeArchivist | `tubearchivistApiKey` | Open **Settings > Application > Integrations** and copy the **API Token**. The Homepage integration requires TubeArchivist 0.4.4 or newer. See the [TubeArchivist settings guide](https://docs.tubearchivist.com/settings/application/) and [Homepage widget guide](https://gethomepage.dev/widgets/services/tubearchivist/). |
| Gitea | `giteaApiToken` | Open the user's **Settings > Applications**, generate an access token, and grant `notifications`, `repository`, and `issue` permissions. Prefer a dedicated user. See the [Homepage Gitea widget guide](https://gethomepage.dev/widgets/services/gitea/). This token is for Gitea, not Forgejo. |
| Paperless-ngx | `paperlessApiKey` | Open **My Profile** from the user menu and use the circular-arrow control to create or rotate the API token. See the [Paperless REST API guide](https://docs.paperless-ngx.com/api/) and [Homepage widget guide](https://gethomepage.dev/widgets/services/paperlessngx/). |
| Nextcloud | `nextcloudToken` | As an administrator, open **Settings > Administration > System** and copy the monitoring `NC-Token`. This is not an ordinary app password. See the [Homepage Nextcloud widget guide](https://gethomepage.dev/widgets/services/nextcloud/). |
| Linkwarden | `linkwardenApiKey` | Open **Settings > Access Tokens**, generate a token for Homepage, and copy it when shown. See the [Homepage Linkwarden widget guide](https://gethomepage.dev/widgets/services/linkwarden/). |
| Pi-hole 6 | `piholeApiKey` | In Pi-hole's settings, generate an application password and use it instead of the primary web password. Homepage also accepts the primary password; an empty value works only when Pi-hole authentication is disabled. See the [Pi-hole API authentication guide](https://docs.pi-hole.net/api/auth/) and [Homepage widget guide](https://gethomepage.dev/widgets/services/pihole/). |
| TrueNAS | `truenasApiKey` | Use the account menu's **API Keys** workflow to create a key for a dedicated read-only integration user where possible. See the [TrueNAS API-key guide](https://www.truenas.com/docs/scale/scaletutorials/toptoolbar/managingapikeys/) and [Homepage widget guide](https://gethomepage.dev/widgets/services/truenas/). |
### Login credentials and API-token pairs

| Service | SOPS keys (under `homepage` unless qualified) | How to obtain them |
| --- | --- | --- |
| qBittorrent | `qbittorrent/username`, `qbittorrent/password` | One canonical username/password pair, shared with ARR. The native hash is derived. Use `nixstead credentials rotate qbittorrent` for explicit rotation; automatic refresh delivers it. |
| Komga | `komgaUsername`, `komgaPassword` | Use the same credentials used to sign in to Komga. Create a dedicated account with only the library access Homepage needs. See the [Homepage Komga widget guide](https://gethomepage.dev/widgets/services/komga/). |
| Grafana | `grafanaUsername`, `grafanaPassword` | Create a dedicated Grafana user and use its normal login credentials. Give it Viewer access to the organization and any data needed for the requested statistics. See the [Homepage Grafana widget guide](https://gethomepage.dev/widgets/services/grafana/). |
| Proxmox | `proxmoxUsername`, `proxmoxPassword` | Create a dedicated user and API token. Grant both the user/group and the privilege-separated token the read-only `PVEAuditor` role at `/` with propagation. Store `user@realm!token-id` as the username and the one-time token secret as the password. Follow Homepage's [Proxmox token procedure](https://gethomepage.dev/configs/proxmox/). |

### Widgets without required credentials

| Service | Requirement |
| --- | --- |
| Tdarr | No credential is required by the current configuration. Homepage supports an optional Tdarr API key, but Nixstead does not request one. See the [Homepage Tdarr widget guide](https://gethomepage.dev/widgets/services/tdarr/). |
| RomM | No credential is required. See the [Homepage RomM widget guide](https://gethomepage.dev/widgets/services/romm/). |
| Prometheus | No credential is required. The widget reads Prometheus's HTTP API through the configured internal target. See the [Homepage Prometheus widget guide](https://gethomepage.dev/widgets/services/prometheus/). |
| Uptime Kuma | No API credential is required. The widget needs a public status-page slug; Nixstead currently uses `home`, corresponding to `/status/home`. See the [Homepage Uptime Kuma widget guide](https://gethomepage.dev/widgets/services/uptimekuma/). |

### Security and troubleshooting

- Treat every API key, token, application password, and Auth Key as a password.
- Prefer a dedicated read-only user or narrowly scoped token whenever the
  application supports it.
- Rotate a credential after accidental disclosure and update the encrypted host
  file before the next activation.
- A `401` or `403` normally indicates a wrong credential or insufficient token
  permissions. A `404` often indicates a widget/application version mismatch.
- Homepage itself has no built-in authentication boundary. Do not expose the
  dashboard publicly merely because widget requests are proxied server-side.

The complete key-name schema is maintained in
[`secrets/secrets.example.yaml`](../../../secrets/secrets.example.yaml).
Registry widget declarations remain the source of truth for which enabled
services consume those keys.
