# Media operations

Nixstead derives services, endpoints, credentials, monitoring and backup policy
from its service registry. API writes are opt-in. Enabling the ARR stack alone
creates no media hierarchy and performs no API reconciliation.

## Storage contract

```nix
nixstead.services.arr = {
  sonarr.enable = true;
  qbittorrent.enable = true;
  storage = {
    root = "/mnt/media/data";
    manageDirectories = true;
    requiredMounts = ["/mnt/media"];
    validation.hardlinks = "warn";
  };
};
```

Declare the filesystem mount separately. A root supplies overrideable defaults:
`torrents`, `torrents/incomplete`, `media/tv`, `media/movies`, `media/music`,
`usenet/incomplete` and `usenet/complete`. Unconfigured paths remain null.
Usenet directories are used only with SABnzbd. Shelfmark requires its own explicit
`paths.ingestDir`. Only selected writers receive directories and permissions.

Explicit qBittorrent `paths.savePath` and `paths.tempPath` take precedence.
Integrations reject conflicting effective download paths. Use normalized absolute
paths without trailing slashes, dot components or symlink components. Download and
library trees must be separate; incomplete and completed Usenet trees must also
be separate. Existing libraries are never moved or reassigned.

Managed missing directories use the media group and mode `2775`. Writers use
`UMask=0002`; application state remains private. Existing directory permissions
are only inspected unless `manageExistingDirectories=true` is also selected.
That choice affects the declared directories, never recursively their contents.
The native application user and sandbox run disposable create, modify, rename,
delete and optional hardlink probes at startup. A common root is exposed through
one writable mount so systemd bind mounts do not themselves cause `EXDEV`.

Both directory creation and writers depend on the real mount units and stop when
those mounts stop. Explicit guards are required for paths under `/mnt` or
`/media`; additional external mounts belong in `storage.requiredMounts`.
An unavailable mount prevents writes to the underlying system disk.

`validation.hardlinks` accepts `disabled`, `warn` (default), or `require`.
Device compatibility is reported separately from an actual hardlink operation.
Probes use disposable files and clean up after failures. `require` makes a failed
probe a service startup failure. CIFS behavior depends on client mount options,
server ACLs and server capabilities, even when device numbers match.

On a deployed host with configured storage:

```sh
nixstead-storage-diagnostic --service sonarr
sudo nixstead-storage-diagnostic --service sonarr --probe
journalctl -u sonarr -u nixstead-arr-directories
```

The probe enters the running service's mount namespace and drops to its actual
UID, GID and supplementary groups. Startup probes additionally inherit the full
service sandbox. This is the separate diagnostic for the real CIFS deployment;
VM results do not establish the NAS's permissions or hardlink support.

## Canonical SOPS credentials

Managed application credentials live once in the encrypted host document:
`sonarr/apiKey`, `radarr/apiKey`, `lidarr/apiKey`, `prowlarr/apiKey`,
`bazarr/apiKey`, `sabnzbd/apiKey`, and `seerr/apiKey`. qBittorrent uses
`qbittorrent/username` and `qbittorrent/password`; its native PBKDF2 hash is
derived at startup. Homepage, Swaparr, exporters and reconcilers receive the same
deployed value. Shared delivery is enabled by selected integrations, monitoring,
Swaparr or Homepage; it can also be selected with `arr.credentials.enable`.

Automatic enrollment is enabled by default with shared credentials or qBittorrent.
A normal rebuild starts `nixstead-credentials-sync.service` before the supported
applications. It reuses existing valid SOPS values, imports a valid native
application key when the SOPS entry is absent, or generates a missing key before
first startup. Missing qBittorrent credentials become username `arr` and a random
password. Its existing password hash cannot be reversed. Each generated value is
saved encrypted and read back successfully before any consumer receives it.

The source must already be an encrypted document decryptable with this host's
`nixstead.secrets.age` identity. The setup wizard enrolls that identity. For a
repository document, the writable path is resolved from `nixstead.secrets.sopsFile`
relative to `nixstead.host.repositoryPath`. External encrypted-directory overrides,
including the deprecated alias, remain supported. A consumer flake with a separate
checkout must explicitly select its writable source if it cannot be inferred:

```nix
nixstead.services.arr.credentials.autoSync.sourceFile = "/etc/nixos/secrets/myhost.yaml";
```

This must be the writable source corresponding to `nixstead.secrets.sopsFile`,
never a `/nix/store` copy. Automatic enrollment changes only encrypted source
content and never commits it. The host needs write access to the file's directory
for atomic replacement. Build and evaluation never decrypt or modify credentials.

Enrollment runs at boot, after relevant rebuild changes, and every minute. It
preserves keys and ciphertext on a no-op run. Changed saved values or restoration
revisions restart affected applications and consumers. Homepage, exporters,
Swaparr and reconcilers share these canonical values; no manual sync or second
rebuild is required. Application administrator bootstrap and relationship policy
choices, such as Seerr root folders and quality profiles, still apply.

Seerr's Jellyfin relationship discovers libraries without copied IDs. Its default
`auto` policy preserves an existing list's choices and selects movie/TV libraries
when that list is empty. `movies-and-tv` also selects future movie/TV libraries.
The connection shares `homepage/jellyfinApiKey` from SOPS; this Jellyfin-issued
key and administrator onboarding are prerequisites, separate from ARR key
generation. See [Seerr library policies](services/seerr.md#selected-relationships).

For installations that deliberately keep the encrypted source offline or
read-only, set `arr.credentials.autoSync.enable = false`. In this manual mode,
initialize the applications, enroll keys, then rebuild to deliver them:

```bash
nixstead --host <host> credentials sync --dry-run
nixstead --host <host> credentials sync
```

Both modes reuse valid SOPS entries and consolidate recognized Homepage/Swaparr
copies into the service-owned entry. Missing, empty, or `replace-me` entries can
be filled; malformed credentials are errors. Conflicting values require an
explicit source selection, for example:

```bash
nixstead --host <host> credentials sync sonarr --from homepage/sonarrApiKey
```

For qBittorrent, repeat `--from` when both fields conflict, for example
`sync qbittorrent --from qbittorrent/username --from homepage/qbittorrentPassword`.

Decryption and malformed-key errors are failures, never missing-key detection.
Synchronization locks the document, preserves unrelated fields and SOPS
recipients, verifies the encrypted update, and replaces the ciphertext atomically.
It refuses to overwrite concurrent source edits. Automatic enrollment fails the
whole transaction on a conflict or source error, publishes a redacted failure,
and retains any previously delivered credentials. Initial dependent startup waits
for successful enrollment. The manual command can complete independent services
and needs the admin SOPS identity; it may request sudo to read application state.
It uses the configured automatic source when present, including custom filenames.

The automatic broker reads back the encrypted result into a root-only runtime
document containing only selected canonical credentials. Delivery units expose
each application's values through mode-0400 files below
`/run/nixstead-credentials/<service>`. Consumers never receive the entire document.
These are delivery copies, not independent secret stores. No plaintext enters Nix
evaluation or the Nix store. Manual mode uses a root-only sops-nix document; missing
entries allow application bootstrap while integrations await credential setup.

SOPS values are supplied to supported native application configuration interfaces,
including Seerr's `API_KEY` environment setting. Optional `apiKeyFiles.<service>`
overrides must reference the same canonical entry declared through `sops.secrets`;
qBittorrent's `usernameFile` and `passwordFile` follow the same rule. These overrides
are unnecessary in automatic mode, which reads the saved source directly and
does not depend on individual sops-nix entries existing before enrollment. Consumer-specific
API-key or downloader-password copies are no longer supported for these services.

```bash
nixstead --host <host> credentials list
nixstead --host <host> credentials show sonarr
sudo nixstead --host <host> credentials show sonarr --runtime
```

`list` prints names, sources and status without values. It distinguishes awaiting
setup, pending deployment, conflicting SOPS sources, invalid credentials,
application drift, and not yet checked. Runtime checks
need permission to read the protected delivery files; unavailable checks never
claim success. `show` prints the canonical SOPS value; `--runtime` explicitly prints
the deployed value and does not need SOPS decryption. Both reveal plaintext only
when requested. qBittorrent passwords cannot be recovered from their hash.

Unexpected application-key changes fail authentication and pause the affected
relationship without changing SOPS or silently adopting the new key. Repair explicitly:

```bash
# Keep SOPS authoritative; request restoration on the next deployment.
nixstead --host <host> credentials sync sonarr --restore
# Deliberately adopt the application's current key instead.
nixstead --host <host> credentials sync sonarr --from application
# Deliberately create a new SOPS key/password.
nixstead --host <host> credentials rotate sonarr
nixstead --host <host> credentials rotate qbittorrent
```

Automatic refresh delivers each saved change within about a minute. In manual
mode, rebuild after saving. `--restore` records a non-secret revision so delivery
also restores an unchanged SOPS value. Native startup configuration
uses the deployed credential; runtime reconciliation reports drift and never
performs an automatic rotation. Credential delivery checks run every minute;
changed deployed values/revisions restart affected consumers. Reconciliation
isolates relationship failures and reports them through `nixstead-status`, which
also shows enrollment success, last successful run and redacted errors. Inspect
`journalctl -u nixstead-credentials-sync -u nixstead-credentials-sync-refresh`
for enrollment failures.

## Ensure relationships

```nix
nixstead.services.arr.integrations = {
  enable = true;
  dryRun = true; # inspect the first run, then explicitly set false
};
```

With both applications and required storage selected, defaults enable categories
and qBittorrent clients for Sonarr/Radarr. Lidarr additionally requires explicit
`lidarr.qualityProfileId` and `lidarr.metadataProfileId`. Toggles are
`storageToQbittorrent.enable`, `qbittorrentToSonarr.enable`,
`qbittorrentToRadarr.enable`, and `qbittorrentToLidarr.enable`.
`sabnzbd.<application>.enable` manages equivalent Usenet relationships.

`prowlarr.<application>.enable` manages application registrations. Its `syncLevel`,
optional category lists and existing tag IDs select synchronization behavior.
Null category/tag settings preserve defaults and UI choices. Optional
`prowlarrSyncProfiles.<label>` declares search/RSS profiles; selecting a profile
on an indexer remains a user action. Indexers and indexer credentials remain
user-owned. `bazarr.sonarr.enable` and `bazarr.radarr.enable` own only connection
fields. Languages, providers, scoring and path mappings remain user choices.

The reconciler fetches current objects before writing and preserves unowned
fields. A private ownership journal records random owner tokens and write intent
before creation. It rejects ambiguous matches and never silently adopts an
existing object by its display name. Existing exact root-folder entries satisfy
the relationship without being edited. Back up the ownership journal together
with application state; losing it intentionally prevents unsafe adoption.

Writes are serialized. Requests have timeouts and readiness has bounded retries.
An interrupted create can be recovered on the next run. Reconciliation runs at
startup, after relevant configuration changes, and every five minutes; a desired
hash does not suppress checks for UI drift or restored application state.
Disabling a relationship stops management without deleting application objects.
There is no pruning mode.

Changing qBittorrent category paths with existing torrents requires the explicit
`relocation="allow"` choice. SABnzbd category path changes require an empty queue.
No adapter moves existing libraries, reassigns media, chooses ARR quality profiles
or deletes user-created clients. Dry runs report only operation and field names,
with no credentials or API response payloads.

```sh
sudo nixstead-status
sudo systemctl start nixstead-arr-reconcile.service
journalctl -u nixstead-arr-reconcile
```

The status includes the last attempt, last success, desired hash and redacted
error. A started run clears the success indicator before API requests so a killed
process cannot leave a previous success advertised. The ownership journal and status are private. Node exporter can collect
`nixstead_arr_reconciliation_success`,
`nixstead_arr_reconciliation_last_success_seconds` and the dry-run indicator.

## Application monitoring

`nixstead.services.arr.monitoring.enable=true` selects registry-supported
Exportarr exporters for enabled Sonarr, Radarr, Lidarr, Prowlarr and Bazarr,
and the native SABnzbd exporter. Override individual selections under `monitoring.services.<id>`.
Exporters bind loopback, use runtime credentials, and generate Prometheus jobs
when Prometheus is enabled. Ports must be unique and separate from application
and other supported exporter ports. Default scrapes are once per minute.
Additional/unknown-queue collection is disabled. qBittorrent and Seerr have no
generated exporter in this implementation.

Grafana can provision the **ARR Application Overview** dashboard from these
metrics with
`nixstead.services.dev.grafana.provisioning.arrDashboard.enable = true`.
Dashboard provisioning and ARR exporter selection remain independent, so a
dashboard may be pointed at another compatible Prometheus data source.

## Exposure and network context

Host services and the supported native applications use authenticated loopback
endpoints for integration traffic. Nginx uses registry targets. A confined
qBittorrent instance is reached through its authenticated loopback socket proxy.
These addresses are not a general container networking contract: custom isolated
containers must supply destinations reachable from their own network context.

After deployment, inspect `ss -lntup` and the actual firewall rules, verify proxy
access from another LAN machine, and verify that direct application ports obey
the selected exposure policy. VM exposure tests cover a real proxied application
and an independent client; each deployment still needs listener verification for
its selected applications.

## References

The [TRaSH layout reference](https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/)
informs the storage relationships. Core reconciliation does not download guide
content. [Exportarr](https://github.com/onedr0p/exportarr#exportarr) defines its
supported application set. See the [support matrix](support-matrix.md) for the
specific checks and limitations.
