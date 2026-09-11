# Service test coverage

Generated from `lib.testCatalogue`; edit suite descriptors and test metadata, then regenerate.

**Scenario** means a runnable check declares the stated evidence; it is not a recorded test pass or exhaustive coverage. **Shared** means catalogue/API assertions only. **Missing** is an explicit coverage gap. Scenario evidence does not automatically confer full support. See [verified scope](../support-matrix.md) for execution evidence.

| Service | Configuration | Runtime | Persistence | Recovery | Failure | Upgrade |
| --- | --- | --- | --- | --- | --- | --- |
| [Actual Budget](#actualbudget) | scenario | scenario | missing | scenario | missing | missing |
| [ARR relationship ownership](#arr-integrations) | scenario | scenario | missing | scenario | missing | missing |
| [Audiobookshelf](#audiobookshelf) | scenario | scenario | missing | scenario | missing | missing |
| [authentik](#authentik) | scenario | scenario | missing | scenario | missing | missing |
| [Bazarr](#bazarr) | scenario | scenario | missing | scenario | missing | missing |
| [CIFS](#cifs) | scenario | scenario | missing | missing | missing | missing |
| [Forgejo](#forgejo) | scenario | scenario | missing | scenario | missing | missing |
| [Gitea](#gitea) | scenario | scenario | missing | scenario | missing | missing |
| [Grafana](#grafana) | scenario | scenario | missing | scenario | missing | missing |
| [Home Assistant](#homeassistant) | scenario | scenario | missing | scenario | missing | missing |
| [Homepage](#homepage) | scenario | scenario | missing | missing | missing | missing |
| [Immich](#immich) | scenario | scenario | missing | scenario | missing | missing |
| [Jellyfin](#jellyfin) | scenario | scenario | missing | scenario | missing | missing |
| [Kavita](#kavita) | scenario | scenario | missing | scenario | missing | missing |
| [Kiwix](#kiwix) | scenario | scenario | missing | missing | missing | missing |
| [Komga](#komga) | scenario | scenario | missing | scenario | missing | missing |
| [Lidarr](#lidarr) | scenario | scenario | missing | scenario | missing | missing |
| [Linkwarden](#linkwarden) | scenario | scenario | missing | scenario | missing | missing |
| [llama.cpp](#llamacpp) | scenario | scenario | missing | missing | missing | missing |
| [Loki](#loki) | scenario | scenario | missing | missing | missing | missing |
| [Mealie](#mealie) | scenario | scenario | missing | scenario | missing | missing |
| [Miniflux](#miniflux) | scenario | scenario | missing | scenario | missing | missing |
| [MongoDB](#mongodb) | scenario | scenario | missing | scenario | missing | missing |
| [n8n](#n8n) | scenario | scenario | missing | scenario | missing | missing |
| [NAS](#nas) | scenario | scenario | missing | missing | missing | missing |
| [Nextcloud](#nextcloud) | scenario | scenario | missing | scenario | missing | missing |
| [Nginx](#nginx) | scenario | scenario | missing | missing | missing | missing |
| [ntfy](#ntfy) | scenario | scenario | missing | scenario | missing | missing |
| [Ollama](#ollama) | scenario | scenario | missing | missing | missing | missing |
| [Open WebUI](#openwebui) | scenario | scenario | missing | scenario | missing | missing |
| [Paperless-ngx](#paperless) | scenario | scenario | missing | scenario | missing | missing |
| [pgAdmin](#pgadmin) | scenario | scenario | missing | scenario | missing | missing |
| [Pi-hole](#pihole) | scenario | scenario | missing | missing | missing | missing |
| [PostgreSQL](#postgresql) | scenario | scenario | missing | scenario | missing | missing |
| [Prometheus](#prometheus) | scenario | scenario | missing | missing | missing | missing |
| [Prowlarr](#prowlarr) | scenario | scenario | missing | scenario | missing | missing |
| [Proxmox](#proxmox) | scenario | scenario | missing | missing | missing | missing |
| [qBittorrent](#qbittorrent) | scenario | scenario | missing | scenario | missing | missing |
| [RabbitMQ](#rabbitmq) | scenario | scenario | missing | scenario | missing | missing |
| [Radarr](#radarr) | scenario | scenario | missing | scenario | missing | missing |
| [Readarr](#readarr) | scenario | scenario | missing | scenario | missing | missing |
| [Redis](#redis) | scenario | scenario | missing | scenario | missing | missing |
| [RomM](#romm) | scenario | scenario | missing | scenario | missing | missing |
| [SABnzbd](#sabnzbd) | scenario | scenario | missing | scenario | missing | missing |
| [Samba](#samba) | scenario | scenario | missing | missing | missing | missing |
| [Scrutiny](#scrutiny) | scenario | scenario | missing | scenario | missing | missing |
| [Seafile](#seafile) | scenario | scenario | missing | scenario | missing | missing |
| [SearXNG](#searxng) | scenario | scenario | missing | scenario | missing | missing |
| [SeaweedFS](#seaweedfs) | scenario | scenario | missing | scenario | missing | missing |
| [Seerr](#seerr) | scenario | scenario | missing | scenario | missing | missing |
| [Shelfmark](#shelfmark) | scenario | scenario | missing | scenario | missing | missing |
| [SnapOtter](#snapotter) | scenario | missing | missing | missing | missing | missing |
| [Sonarr](#sonarr) | scenario | scenario | missing | scenario | missing | missing |
| [stable-diffusion.cpp](#stablediffusioncpp) | scenario | missing | missing | missing | missing | missing |
| [Stirling PDF](#stirlingpdf) | scenario | scenario | missing | missing | missing | missing |
| [Swaparr](#swaparr) | scenario | scenario | not-applicable | not-applicable | missing | not-applicable |
| [Syncthing](#syncthing) | scenario | scenario | missing | scenario | missing | missing |
| [Tailscale](#tailscale) | scenario | scenario | missing | missing | missing | missing |
| [Tdarr](#tdarr) | scenario | scenario | missing | scenario | missing | missing |
| [Tdarr node](#tdarr-node) | scenario | scenario | not-applicable | not-applicable | missing | not-applicable |
| [TrueNAS](#truenas) | scenario | scenario | missing | missing | missing | missing |
| [TubeArchivist](#tubearchivist) | scenario | scenario | missing | scenario | missing | missing |
| [Uptime Kuma](#uptimekuma) | scenario | scenario | missing | scenario | missing | missing |
| [Vaultwarden](#vaultwarden) | scenario | scenario | missing | scenario | missing | missing |
| [Wallabag](#wallabag) | scenario | scenario | missing | scenario | missing | missing |
| [WireGuard](#wireguard) | scenario | scenario | missing | missing | missing | missing |

<a id="actualbudget"></a>
## Actual Budget

Support: limited. State: stateful.

Suite: [tests/services/actualbudget/default.nix](../../tests/services/actualbudget/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-actualbudget-config`: Independent selection, native listener/exposure, effective state paths, default DynamicUser and custom account ownership, mount ordering and required recovery inputs.
- `service-actualbudget-recovery`: One clean encrypted Borg restore of custom named-user state and separate budget storage; native readiness, original token and file-marker bytes.
- `service-actualbudget-recovery-dynamic`: Default DynamicUser state backing bytes erased and restored once from Borg, followed by native readiness, original authentication and marker checks.

Limitations: Focused configuration/startup/backup-restore smoke. Budget/transaction workflows, sync failure cases, bank feeds, OIDC, encryption, repeated lifecycle/reboot testing, upgrades and ARM runtime are outside this contract. No test changes between pinned application revisions.

<a id="arr-integrations"></a>
## ARR relationship ownership

Support: limited. State: stateful.

Suite: [tests/services/arr-integrations/default.nix](../../tests/services/arr-integrations/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-arr-integrations-config`: Opt-in relationships, independently disabled targets, ownership-journal identity, runtime-only credentials, backup manifest and missing dependency/storage assertions.
- `service-arr-integrations-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="audiobookshelf"></a>
## Audiobookshelf

Support: limited. State: stateful.

Suite: [tests/services/audiobookshelf/default.nix](../../tests/services/audiobookshelf/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-audiobookshelf-config`: Independent child selection, native listener/path/account overrides, mount ordering and applicable proxy/card/exposure and recovery wiring.
- `service-audiobookshelf-recovery`: One clean encrypted Borg restore of the native application root, followed by HTTP readiness and original marker verification.

Limitations: Focused startup and application-state backup/restore smoke. Library workflows, playback/reading progress, source-content recovery, repeated lifecycle/reboot testing, exhaustive failures, upgrades and ARM runtime are outside this contract. No test changes between pinned application revisions.

<a id="authentik"></a>
## authentik

Support: limited. State: stateful.

Suite: [tests/services/authentik/default.nix](../../tests/services/authentik/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-authentik-config`: Isolated server/worker/database bootstrap, custom SQL port, private internal listeners, native state/mounts, secret ownership/rotation and combined SQL/state archive.
- `service-authentik-recovery`: One shipped Borg backup/restore of native PostgreSQL and state roots, checking readiness and explicit test-owned SQL/file markers.

Limitations: Application identity/provider workflows, repeated lifecycle, outage matrices, proxy interactions and cross-version recovery are outside this wiring smoke fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="bazarr"></a>
## Bazarr

Support: limited. State: stateful.

Suite: [tests/services/bazarr/default.nix](../../tests/services/bazarr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-bazarr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-bazarr-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="cifs"></a>
## CIFS

Support: limited. State: stateless.

Suite: [tests/services/cifs/default.nix](../../tests/services/cifs/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-cifs-config`: Isolated native authenticated automount, custom ownership/read-only options and runtime private credentials; empty shares and duplicate mounts rejected; no local SMB server.
- `service-cifs-runtime`: A real Samba peer and the native CIFS automounts start with runtime SOPS authentication, and both configured shares return the expected bytes over CIFS.

Limitations: Remote content recovery belongs to the server. Credential rotation, peer loss, reboot reconnect, write policy, backup destination/server-loss recovery, cross-version upgrades and ARM runtime remain unverified. No test changes between pinned application revisions.

<a id="forgejo"></a>
## Forgejo

Support: limited. State: stateful.

Suite: [tests/services/forgejo/default.nix](../../tests/services/forgejo/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-forgejo-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-forgejo-recovery`: One clean Borg restore of native SQLite application and separate repository roots, followed by readiness and independent filesystem markers.

Limitations: Repository, issue and attachment workflows, external databases, SSH, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified. No test changes between pinned application revisions.

<a id="gitea"></a>
## Gitea

Support: limited. State: stateful.

Suite: [tests/services/gitea/default.nix](../../tests/services/gitea/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-gitea-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-gitea-recovery`: One clean Borg restore of native SQLite application and separate repository roots, followed by readiness and independent filesystem markers.

Limitations: Repository, issue and attachment workflows, external databases, SSH, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified. No test changes between pinned application revisions.

<a id="grafana"></a>
## Grafana

Support: limited. State: stateful.

Suite: [tests/services/grafana/default.nix](../../tests/services/grafana/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-grafana-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings, encrypted-source credential paths and essential SQLite backup wiring.
- `service-grafana-recovery`: One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="homeassistant"></a>
## Home Assistant

Support: limited. State: stateful.

Suite: [tests/services/homeassistant/default.nix](../../tests/services/homeassistant/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-homeassistant-config`: Isolated native state/listener/trusted proxy, backup path and mount guard, invalid path and proxy/card/firewall selection.
- `service-homeassistant-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="homepage"></a>
## Homepage

Support: limited. State: stateless.

Suite: [tests/services/homepage/default.nix](../../tests/services/homepage/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-homepage-config`: Selected and disabled cards/widgets, custom endpoint/domain/shortcut, runtime placeholders/environment templates, allowed hosts and native listener/proxy/firewall.
- `service-homepage-runtime`: The native dashboard and a bounded TrueNAS widget peer start; the configured card, shortcut, placeholder and authenticated widget response render successfully.

Limitations: The widget peer implements only the exact legacy TrueNAS REST endpoints exercised locally. Credential rotation, dependency outages, restart/reboot, browser layout/accessibility, other widget types, live TrueNAS/WebSocket API compatibility, ARM runtime and upgrades are unverified. No test changes between pinned application revisions.

<a id="immich"></a>
## Immich

Support: limited. State: stateful.

Suite: [tests/services/immich/default.nix](../../tests/services/immich/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-immich-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-immich-recovery`: One clean combined PostgreSQL/media Borg restore, followed by HTTP readiness and an independent filesystem marker.

Limitations: Photo/album/account workflows, machine learning, external libraries, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified. No test changes between pinned application revisions.

<a id="jellyfin"></a>
## Jellyfin

Support: limited. State: stateful.

Suite: [tests/services/jellyfin/default.nix](../../tests/services/jellyfin/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-jellyfin-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-jellyfin-recovery`: One clean Borg restore of native application and separate configuration roots, followed by HTTP readiness and independent filesystem markers.

Limitations: Source-media libraries, account/library/playstate workflows, GPU behavior, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified. No test changes between pinned application revisions.

<a id="kavita"></a>
## Kavita

Support: limited. State: stateful.

Suite: [tests/services/kavita/default.nix](../../tests/services/kavita/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-kavita-config`: Independent child selection, native listener/path/account overrides, mount ordering and applicable proxy/card/exposure and recovery wiring.
- `service-kavita-recovery`: One clean encrypted Borg restore of the native application root, followed by HTTP readiness and original marker verification. Kavita also retains the original generated signing key.

Limitations: Focused startup and application-state backup/restore smoke. Library workflows, playback/reading progress, source-content recovery, repeated lifecycle/reboot testing, exhaustive failures, upgrades and ARM runtime are outside this contract. A signing key outside the application root needs separate backup; this fixture keeps it inside the root. No test changes between pinned application revisions.

<a id="kiwix"></a>
## Kiwix

Support: limited. State: stateless.

Suite: [tests/services/kiwix/default.nix](../../tests/services/kiwix/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-kiwix-config`: Independent selection, child override, custom listener/path settings, native wiring, monitored library regeneration and applicable proxy/card/firewall, credential and backup configuration.
- `service-kiwix-runtime`: Native Kiwix generates a valid empty catalogue and serves it on the configured loopback listener without a systemd restart.

Limitations: The runtime check is intentionally a fast startup/readiness smoke. Archive loading, full-text search, browser behavior, ARM runtime and upgrades remain unverified. Source ZIMs remain externally owned; unique archives need a separate storage recovery contract. Only the generated library index is reconstructable, so no backup claim applies. No test changes between pinned application revisions.

<a id="komga"></a>
## Komga

Support: limited. State: stateful.

Suite: [tests/services/komga/default.nix](../../tests/services/komga/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-komga-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-komga-recovery`: The native service reaches its readiness API, then the shipped backup tool captures initialized state and one clean Borg restore into empty application storage returns the service with an exact smoke marker.

Limitations: The combined startup/recovery check is intentionally a fast service-wiring smoke on x86_64. Accounts, library operations, readers, external authentication, ARM runtime and pinned upgrades remain unverified. Source books remain externally owned and need their storage owner's recovery contract. Komga's archive covers its own database, settings, indexes and internal task state only. No test changes between pinned application revisions.

<a id="lidarr"></a>
## Lidarr

Support: limited. State: stateful.

Suite: [tests/services/lidarr/default.nix](../../tests/services/lidarr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-lidarr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-lidarr-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. The existing /var/lib/lidarr archive layout is preserved; custom native dataDir recovery is unverified. No test changes between pinned application revisions.

<a id="linkwarden"></a>
## Linkwarden

Support: limited. State: stateful.

Suite: [tests/services/linkwarden/default.nix](../../tests/services/linkwarden/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-linkwarden-config`: Independent enable/disable and parent override, custom published listener/state volumes, private dependencies, runtime SOPS templates, backup database wiring, proxy/card/firewall and invalid port/image inputs.
- `service-linkwarden-recovery`: Pinned application and dependency startup with runtime SOPS credentials, HTTP readiness, one shipped PostgreSQL/Borg backup and clean restore, and the original file marker after recovery.

Limitations: No business workflow, search/queue correctness, failure or restart/reboot matrix, cross-version upgrade, or ARM runtime claim. Runtime SOPS sources remain outside the application backup and must be retained independently. No test changes between pinned application revisions.

<a id="llamacpp"></a>
## llama.cpp

Support: limited. State: stateless.

Suite: [tests/services/llamacpp/default.nix](../../tests/services/llamacpp/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-llamacpp-config`: Independent child selection; native model/context/threads and managed listeners, Ollama dependency/read-only model bind, proxy/card/firewall.
- `service-llamacpp-runtime`: Native llama.cpp starts with the small immutable GGUF fixture and reaches its configured loopback health endpoint.

Limitations: The 19 MB TinyStories GGUF exists only so the native server can start. Inference semantics, model-loss behavior, restart/reboot, production quality, large-model capacity, GPU, ARM runtime and cross-version behavior remain unverified by this smoke. Read-only source bytes are configuration-owned; no unique model or retained-output backup is implied. No test changes between pinned application revisions.

<a id="loki"></a>
## Loki

Support: limited. State: stateful.

Suite: [tests/services/loki/default.nix](../../tests/services/loki/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-loki-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-loki-runtime`: Native single-process Loki starts and reaches its readiness endpoint on the configured loopback listener.

Limitations: History is deliberately disposable in the registry policy and earns no backup claim. Log ingestion/query semantics, retained history, restart/reboot, wall-clock retention deletion, external object storage, distributed operation and cross-version upgrades are unverified by this smoke. No test changes between pinned application revisions.

<a id="mealie"></a>
## Mealie

Support: limited. State: stateful.

Suite: [tests/services/mealie/default.nix](../../tests/services/mealie/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-mealie-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, fixed effective data root, native dynamic identity and essential SQLite/key recovery inputs.
- `service-mealie-recovery`: One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="miniflux"></a>
## Miniflux

Support: limited. State: stateful.

Suite: [tests/services/miniflux/default.nix](../../tests/services/miniflux/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-miniflux-config`: Independent enable/disable, parent override, custom listener and PostgreSQL port, invalid port, exposure and card/proxy selection, plus credential override and database ownership/bootstrap wiring.
- `service-miniflux-recovery`: One shipped encrypted Borg backup and erased-state restore, followed by native readiness and SQL and file markers checking the configured archive roots.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. Recovery retains the independently provisioned PostgreSQL server and role. No test changes between pinned application revisions.

<a id="mongodb"></a>
## MongoDB

Support: limited. State: stateful.

Suite: [tests/services/mongodb/default.nix](../../tests/services/mongodb/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-mongodb-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-mongodb-recovery`: Native MongoDB startup with its runtime bootstrap credential, one stopped-WiredTiger encrypted Borg backup and clean restore, and readiness with the exact marker document after recovery.

Limitations: Account/role behavior, credential rotation, failure cases, restart/reboot, replica sets, sharding, alternative storage/encryption settings, exhaustive collection-page integrity, ARM execution and cross-version upgrades are outside this startup/recovery smoke. No test changes between pinned application revisions.

<a id="n8n"></a>
## n8n

Support: limited. State: stateful.

Suite: [tests/services/n8n/default.nix](../../tests/services/n8n/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-n8n-config`: Independent selection, listener/exposure, secure cookies and proxy/card settings; native runtime credential paths and conditional default SQLite/config/encryption-material recovery guards.
- `service-n8n-recovery`: Native backend HTTP readiness, one shipped backup and clean Borg restore, and continuity of the original encryption identity and small state marker after deleting the owned directory.

Limitations: The fast native SQLite/backend profile does not test workflow internals, encrypted credential use, browser behavior, third-party APIs, queue workers, external database recovery or cross-version upgrades. AArch64 coverage is configuration evaluation only. No test changes between pinned application revisions.

<a id="nas"></a>
## NAS

Support: limited. State: stateful.

Suite: [tests/services/nas/default.nix](../../tests/services/nas/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-nas-config`: Independent NAS children, explicit data/parity devices, mergerfs mount dependency, SnapRAID parity/content configuration and missing-disk assertions.
- `service-nas-runtime`: Three disposable native filesystems and the configured mergerfs pool mount successfully, and one bounded writer can create and read exact bytes through the pool.

Limitations: SnapRAID sync/scrub/repair, missing-mount handling, restart/reboot, independent backup, multiple-disk loss, physical devices and authenticated sharing integration remain unverified by the maintained smoke. Parity is not an independent archive recovery contract. No test changes between pinned application revisions.

<a id="nextcloud"></a>
## Nextcloud

Support: limited. State: stateful.

Suite: [tests/services/nextcloud/default.nix](../../tests/services/nextcloud/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-nextcloud-config`: Independent enable/disable, parent override, custom port, proxy/card, separate home/data and credential override.
- `service-nextcloud-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: SQLite configuration only; PostgreSQL, external storage, application workflows, repeated lifecycle, failure matrices, upgrades and ARM runtime remain unverified. No test changes between pinned application revisions.

<a id="nginx"></a>
## Nginx

Support: limited. State: stateful.

Suite: [tests/services/nginx/default.nix](../../tests/services/nginx/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-nginx-config`: Isolated native listeners and registry vhosts, child disable, backend isolation, renewal/secret ordering and rejected incomplete/store-key/invalid renewal CA settings.
- `service-nginx-runtime`: Nginx, its generated local CA and a registry proxy start; an independent client trusts that CA, reaches the proxy and cannot reach the loopback backend directly.

Limitations: Local-CA archive recovery, rotation/retrust, repeated lifecycle, upstream failures, websocket behavior, external certificate authorities, ARM runtime and upgrades remain unverified by this fast smoke. No test changes between pinned application revisions.

<a id="ntfy"></a>
## ntfy

Support: limited. State: stateful.

Suite: [tests/services/ntfy/default.nix](../../tests/services/ntfy/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-ntfy-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-ntfy-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="ollama"></a>
## Ollama

Support: limited. State: stateful.

Suite: [tests/services/ollama/default.nix](../../tests/services/ollama/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-ollama-config`: Independent child selection; native loopback/model mount/media access, CPU package default, custom port/proxy/card/firewall and invalid model path.
- `service-ollama-runtime`: Native Ollama starts with the configured custom model directory and reaches its loopback version endpoint.

Limitations: Model import/inference, model persistence or backup, restart/reboot, malformed requests, remote registries, GPU, ARM runtime, large models and cross-version execution are unverified by this startup smoke. Unique imported weights and definitions remain user-owned durable state without a passing archive recovery fixture. No test changes between pinned application revisions.

<a id="openwebui"></a>
## Open WebUI

Support: limited. State: stateful.

Suite: [tests/services/openwebui/default.nix](../../tests/services/openwebui/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-openwebui-config`: Independent child selection; local/external backend requirements, custom native listener, runtime credential file, stopped-writer state/key archive and native path override.
- `service-openwebui-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="paperless"></a>
## Paperless-ngx

Support: limited. State: stateful.

Suite: [tests/services/paperless/default.nix](../../tests/services/paperless/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-paperless-config`: Independent enable/disable, parent override, custom port, proxy/card/firewall, separate data/media/inbox and native key ownership.
- `service-paperless-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="pgadmin"></a>
## pgAdmin

Support: limited. State: stateful.

Suite: [tests/services/pgadmin/default.nix](../../tests/services/pgadmin/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-pgadmin-config`: Independent enable/disable, parent override, custom listener, exposure and card/proxy selection, native credential/package wiring, and local SQLite recovery inputs following a supported custom filename.
- `service-pgadmin-recovery`: One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. Managed PostgreSQL databases have a separate recovery owner. No test changes between pinned application revisions.

<a id="pihole"></a>
## Pi-hole

Support: limited. State: stateless.

Suite: [tests/services/pihole/default.nix](../../tests/services/pihole/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-pihole-config`: Remote endpoint/admin/API proxy and DNS-sync opt-in profiles, private runtime DNS/widget credentials, Pi-hole widget revision, disabled removal and no local upstream.
- `service-pihole-runtime`: The shipped opt-in DNS sync starts, authenticates to a bounded local Pi-hole v6 API peer and applies the configured owned records once.

Limitations: The local peer implements only the Pi-hole v6 authentication and DNS-host configuration endpoints used by the adapter. Idempotence, credential rotation, failure handling, reboot, live Pi-hole compatibility, appliance databases/recovery, DNS query behavior, ARM runtime and upgrades remain outside this smoke. Externally hosted endpoint; no external system is started or recovered here. No test changes between pinned application revisions.

<a id="postgresql"></a>
## PostgreSQL

Support: limited. State: stateful.

Suite: [tests/services/postgresql/default.nix](../../tests/services/postgresql/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-postgresql-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-postgresql-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: The marker uses a separate application database; custom objects in the postgres maintenance database can prevent global role restoration and are outside this smoke. Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="prometheus"></a>
## Prometheus

Support: limited. State: stateful.

Suite: [tests/services/prometheus/default.nix](../../tests/services/prometheus/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-prometheus-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-prometheus-runtime`: Native Prometheus and node-exporter start, and Prometheus reaches its readiness endpoint on the configured loopback listener.

Limitations: History is deliberately disposable in the registry policy and earns no backup claim. Scraping/query semantics, retained history, restart/reboot, wall-clock retention expiry, remote storage, distributed operation and cross-version upgrades are unverified by this smoke; native runtime coverage is x86_64 only. No test changes between pinned application revisions.

<a id="prowlarr"></a>
## Prowlarr

Support: limited. State: stateful.

Suite: [tests/services/prowlarr/default.nix](../../tests/services/prowlarr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-prowlarr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-prowlarr-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="proxmox"></a>
## Proxmox

Support: limited. State: stateless.

Suite: [tests/services/proxmox/default.nix](../../tests/services/proxmox/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-proxmox-config`: Remote HTTPS endpoint, websocket/self-signed proxy, card/token placeholders, disabled removal, invalid port and absence of local upstream/firewall/state.
- `service-proxmox-runtime`: Homepage and a self-signed bounded Proxmox HTTPS peer start, and the widget returns the configured cluster resources using runtime SOPS API-token credentials.

Limitations: The peer implements only the cluster/resources endpoint used by the Homepage widget. Credential rotation, dependency failures, restart/reboot, live Proxmox compatibility, browser login, external VM/container backup, ARM runtime and upgrades are outside this smoke. Externally hosted endpoint; no external system is started or recovered here. No test changes between pinned application revisions.

<a id="qbittorrent"></a>
## qBittorrent

Support: limited. State: stateful.

Suite: [tests/services/qbittorrent/default.nix](../../tests/services/qbittorrent/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-qbittorrent-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-qbittorrent-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="rabbitmq"></a>
## RabbitMQ

Support: limited. State: stateful.

Suite: [tests/services/rabbitmq/default.nix](../../tests/services/rabbitmq/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-rabbitmq-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, native state/cookie backup and runtime credential/bootstrap wiring with password input over stdin.
- `service-rabbitmq-recovery`: One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="radarr"></a>
## Radarr

Support: limited. State: stateful.

Suite: [tests/services/radarr/default.nix](../../tests/services/radarr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-radarr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-radarr-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. The existing /var/lib/radarr archive layout is preserved; custom native dataDir recovery is unverified. No test changes between pinned application revisions.

<a id="readarr"></a>
## Readarr

Support: limited. State: stateful.

Suite: [tests/services/readarr/default.nix](../../tests/services/readarr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-readarr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-readarr-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="redis"></a>
## Redis

Support: limited. State: stateful.

Suite: [tests/services/redis/default.nix](../../tests/services/redis/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-redis-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-redis-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="romm"></a>
## RomM

Support: limited. State: stateful.

Suite: [tests/services/romm/default.nix](../../tests/services/romm/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-romm-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-romm-recovery`: One clean encrypted Borg restore of application paths and native database export into empty application storage and a fresh database volume; application readiness and file markers are checked afterward.

Limitations: Focused startup and backup/restore smoke only; no populated library, account/content workflows, repeated reboot, detailed failures, upgrade or ARM runtime claim. External metadata and internet video/ROM acquisition are outside the fixture. No test changes between pinned application revisions.

<a id="sabnzbd"></a>
## SABnzbd

Support: limited. State: stateful.

Suite: [tests/services/sabnzbd/default.nix](../../tests/services/sabnzbd/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-sabnzbd-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-sabnzbd-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="samba"></a>
## Samba

Support: limited. State: stateful.

Suite: [tests/services/samba/default.nix](../../tests/services/samba/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-samba-config`: Independent Samba selection, authenticated custom shares/users/read-only policy, explicit firewall, no directory ownership mutation and invalid/reserved share rejection.
- `service-samba-runtime`: Native Samba starts; an authenticated client writes and reads exact bytes through the selected share, while the configured read-only share rejects a write.

Limitations: Samba account-state recovery, credential rotation, guest/unlisted access, missing storage, restart/reboot, owned share recovery, ARM runtime and upgrades remain unverified. Externally owned bytes need their storage owner's recovery fixture. No test changes between pinned application revisions.

<a id="scrutiny"></a>
## Scrutiny

Support: limited. State: stateful.

Suite: [tests/services/scrutiny/default.nix](../../tests/services/scrutiny/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-scrutiny-config`: Isolated native web/collector/InfluxDB selection and ports, read-only path overrides rejected, private database and combined two-directory archive.
- `service-scrutiny-recovery`: One shipped Borg backup and empty-state restore of both native state directories, checking readiness and independent test-owned file markers.

Limitations: SMART report ingestion, historical metrics, physical disk access and repeated lifecycle or outage scenarios are outside this wiring smoke fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="seafile"></a>
## Seafile

Support: limited. State: stateful.

Suite: [tests/services/seafile/default.nix](../../tests/services/seafile/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-seafile-config`: Independent selection, custom listener/state volumes, private dependencies, runtime credentials, all-three-database recovery policy and proxy/card/exposure behavior.
- `service-seafile-recovery`: One clean encrypted Borg restore of an empty application tree and MariaDB volume, including all three databases; readiness, initial administrator identity, native configuration and marker bytes.

Limitations: Focused startup and backup/restore smoke for community 11.0.13; library workflows, client synchronization, encrypted libraries, detailed failure matrices, repeated lifecycle/reboot testing, clusters, upgrades and ARM runtime are outside this contract. SQL preflight checks expected database sections and completion marker, not arbitrary SQL semantics or every individual block. No test changes between pinned application revisions.

<a id="searxng"></a>
## SearXNG

Support: limited. State: stateful.

Suite: [tests/services/searxng/default.nix](../../tests/services/searxng/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-searxng-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-searxng-recovery`: Native SearXNG starts on its loopback listener with a small local engine, then one encrypted backup and clean Borg restore recovers its server secret and query readiness.

Limitations: Owned state is the generated server secret, not search history. The combined startup/recovery check is an intentionally fast service-wiring smoke; public-engine compatibility, ranking, limiter behavior, browser UI and external proxy behavior remain unverified. Runtime and recovery are x86_64 only; ARM configuration is evaluated separately. Redis is a disposable limiter cache, and no cross-version upgrade is claimed. No test changes between pinned application revisions.

<a id="seaweedfs"></a>
## SeaweedFS

Support: limited. State: stateful.

Suite: [tests/services/seaweedfs/default.nix](../../tests/services/seaweedfs/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-seaweedfs-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-seaweedfs-recovery`: One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="seerr"></a>
## Seerr

Support: limited. State: stateful.

Suite: [tests/services/seerr/default.nix](../../tests/services/seerr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-seerr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-seerr-recovery`: One clean Borg restore of canonical private application state, followed by native HTTP readiness and an independent filesystem marker.

Limitations: Accounts, movie/TV requests, external Jellyfin/TMDB/ARR peers, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified. No test changes between pinned application revisions.

<a id="shelfmark"></a>
## Shelfmark

Support: limited. State: stateful.

Suite: [tests/services/shelfmark/default.nix](../../tests/services/shelfmark/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-shelfmark-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-shelfmark-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="snapotter"></a>
## SnapOtter

Support: limited. State: stateful.

Suite: [tests/services/snapotter/default.nix](../../tests/services/snapotter/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-snapotter-config`: Independent enable/disable and parent override, custom published listener/state volumes, private dependencies, runtime SOPS templates, backup database wiring, proxy/card/firewall and invalid port/image inputs.

Limitations: Native startup and clean restore remain unverified: the exact supported amd64 application image contains about 3.56 GiB of compressed layers, disproportionate to the maintained fast smoke baseline. No business-workflow, failure, lifecycle or upgrade claim. No test changes between pinned application revisions.

<a id="sonarr"></a>
## Sonarr

Support: limited. State: stateful.

Suite: [tests/services/sonarr/default.nix](../../tests/services/sonarr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-sonarr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-sonarr-recovery`: One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only. The existing /var/lib/sonarr archive layout is preserved; custom native dataDir recovery is unverified. No test changes between pinned application revisions.

<a id="stablediffusioncpp"></a>
## stable-diffusion.cpp

Support: limited. State: unknown.

Suite: [tests/services/stablediffusioncpp/default.nix](../../tests/services/stablediffusioncpp/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-stablediffusioncpp-config`: Independent child selection; split models and mount conditions, native command/resource overrides, missing/duplicate/reserved model rejection, proxy/card/firewall.

Limitations: Healthy native startup is unverified: sd-server loads a complete compatible model before listening, and the fast suite has no small compatible checkpoint fixture. Image generation, retained output/asset recovery and GPU profiles remain unverified. No test changes between pinned application revisions.

<a id="stirlingpdf"></a>
## Stirling PDF

Support: limited. State: stateless.

Suite: [tests/services/stirlingpdf/default.nix](../../tests/services/stirlingpdf/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-stirlingpdf-config`: Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.
- `service-stirlingpdf-runtime`: The native service reaches its configured loopback listener without a systemd restart and serves its HTTP endpoint under the supported stateless profile.

Limitations: The supported profile has authentication and persistent user settings disabled, so temporary processing data is reconstructable and no backup applies. Enabling accounts or retained settings requires a separate persistence/recovery contract. The runtime check is intentionally a startup/readiness smoke. PDF operations, OCR, office conversion, browser behavior, ARM runtime, large-document performance and upgrades remain unverified. No test changes between pinned application revisions.

<a id="swaparr"></a>
## Swaparr

Support: limited. State: stateless.

Suite: [tests/services/swaparr/default.nix](../../tests/services/swaparr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-swaparr-config`: Independent target selection, container endpoint/image, runtime-only credentials, no persistent volumes, parent disable and manual Readarr credential wiring.
- `service-swaparr-runtime`: Shared native ARR startup smoke: configured HTTP readiness, private runtime SOPS credentials, one selected shipped reconciliation and pinned dry-run Swaparr workers; one VM is reused by the family checks.
- persistence: not applicable. This worker owns no durable application records; its runtime/cache is reconstructed.
- recovery: not applicable. Disposable worker state is reconstructed; server state and source bytes belong to separate owners.
- upgrade: not applicable. This worker has no durable application-state migration; compatibility across revisions remains unverified.

Limitations: The combined x86_64 ARR smoke passed. Its peer backup/restore activity does not establish Swaparr recovery; worker state is reconstructable. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup fixture. Source/download bytes have separate owners. Runtime targets x86_64; ARM has configuration evaluation only. No test changes between pinned application revisions.

<a id="syncthing"></a>
## Syncthing

Support: limited. State: stateful.

Suite: [tests/services/syncthing/default.nix](../../tests/services/syncthing/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-syncthing-config`: Isolated child/native GUI/peer selection, transfer/discovery firewall, state/index/credential destinations, bootstrap order, unowned folders and identity-only archive.
- `service-syncthing-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="tailscale"></a>
## Tailscale

Support: limited. State: stateful.

Suite: [tests/services/tailscale/default.nix](../../tests/services/tailscale/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-tailscale-config`: Isolated native daemon, routing mode and advertised routes, no implicit enrollment credentials, invalid routing enum and absence of HTTP proxy/card.
- `service-tailscale-runtime`: The native daemon starts, exposes its local socket and reports NeedsLogin with no assigned Tailscale addresses; no control-plane enrollment is performed.

Limitations: Control-plane enrollment/connectivity, enrolled identity continuity and secure identity restore or re-enrollment remain unverified. No test changes between pinned application revisions.

<a id="tdarr"></a>
## Tdarr

Support: limited. State: stateful.

Suite: [tests/services/tdarr/default.nix](../../tests/services/tdarr/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-tdarr-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-tdarr-recovery`: One clean encrypted Borg restore of the stopped native server root, followed by HTTP readiness and an independent marker check.

Limitations: Focused startup and server-state backup/restore smoke; no transcode jobs, media files, detailed node reconnection, repeated reboot or ARM runtime claim. No test changes between pinned application revisions.

<a id="tdarr-node"></a>
## Tdarr node

Support: limited. State: stateless.

Suite: [tests/services/tdarr-node/default.nix](../../tests/services/tdarr-node/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-tdarr-node-config`: Independent node/server selection, custom identity/data/cache/media paths, mount permissions and rejected missing identity; no local HTTP card or backup.
- `service-tdarr-node-runtime`: Native worker startup within the shared Tdarr server recovery smoke, with workers paused; the alias adds no separate VM.
- persistence: not applicable. This worker owns no durable application records; its runtime/cache is reconstructed.
- recovery: not applicable. Disposable worker state is reconstructed; server state and source bytes belong to separate owners.
- upgrade: not applicable. This worker has no durable application-state migration; compatibility across revisions remains unverified.

Limitations: Real server reconnect and CPU job safety require the server/node integration fixture; node cache is disposable. No test changes between pinned application revisions.

<a id="truenas"></a>
## TrueNAS

Support: limited. State: stateless.

Suite: [tests/services/truenas/default.nix](../../tests/services/truenas/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-truenas-config`: Remote endpoint, websocket proxy, card/key placeholders, disabled removal, invalid port and absence of local upstream/firewall/storage mounts.
- `service-truenas-runtime`: Homepage and a bounded TrueNAS peer start, and one authenticated widget status/alert response succeeds with the runtime SOPS key.

Limitations: The local peer implements only the exact legacy REST endpoints consumed by the Homepage widget. Credential rotation, dependency failures, restart/reboot, live appliance compatibility, pool/snapshot recovery, storage mounts, ARM runtime and upgrades remain outside this smoke. Externally hosted endpoint; no external system is started or recovered here. No test changes between pinned application revisions.

<a id="tubearchivist"></a>
## TubeArchivist

Support: limited. State: stateful.

Suite: [tests/services/tubearchivist/default.nix](../../tests/services/tubearchivist/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-tubearchivist-config`: Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.
- `service-tubearchivist-recovery`: One clean encrypted Borg restore of application paths and native database export into empty application storage and a fresh database volume; application readiness and file markers are checked afterward.

Limitations: Focused startup and backup/restore smoke only; no populated library, account/content workflows, repeated reboot, detailed failures, upgrade or ARM runtime claim. External metadata and internet video/ROM acquisition are outside the fixture. No test changes between pinned application revisions.

<a id="uptimekuma"></a>
## Uptime Kuma

Support: limited. State: stateful.

Suite: [tests/services/uptimekuma/default.nix](../../tests/services/uptimekuma/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-uptimekuma-config`: Independent enable/disable, parent override, custom port and volume, pinned image and proxy/card/firewall wiring.
- `service-uptimekuma-recovery`: Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.

Limitations: Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately. No test changes between pinned application revisions.

<a id="vaultwarden"></a>
## Vaultwarden

Support: limited. State: stateful.

Suite: [tests/services/vaultwarden/default.nix](../../tests/services/vaultwarden/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `python`: Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.
- `service-vaultwarden-config`: Isolated native access/signups, runtime admin token, stateVersion-dependent roots and aliases, known SQLite/key requirements, optional private snapshot identity/schedule/mount dependencies, and invalid snapshot profiles.
- `service-vaultwarden-recovery`: One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.

Limitations: The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. This fixture uses native SQLite and the legacy stateVersion root; browser/client encryption and native snapshot failure scenarios are outside the maintained smoke. No test changes between pinned application revisions.

<a id="wallabag"></a>
## Wallabag

Support: limited. State: stateful.

Suite: [tests/services/wallabag/default.nix](../../tests/services/wallabag/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-wallabag-config`: Independent enable/disable and parent override, custom published listener/state volumes, private dependencies, runtime SOPS templates, backup database wiring, proxy/card/firewall and invalid port/image inputs.
- `service-wallabag-recovery`: The exact digest-pinned stack reaches its loopback endpoint, then the shipped backup tool captures MariaDB and application files and one clean Borg restore returns it with an exact marker.

Limitations: The combined startup/recovery check is intentionally a fast service-wiring smoke on x86_64. Accounts, saved pages, remote content handling, ARM runtime and pinned upgrades remain unverified. Redis is treated as a disposable cache; durable Wallabag state is the MariaDB database and application image directory. No test changes between pinned application revisions.

<a id="wireguard"></a>
## WireGuard

Support: limited. State: stateless.

Suite: [tests/services/wireguard/default.nix](../../tests/services/wireguard/default.nix).

- `public-module-api`: Shared registry/public API assertions; does not establish every isolated service contract.
- `service-wireguard-config`: Host and namespace selection, private SOPS rotation, explicit handshake firewall, bound service lifecycle, child disable and missing/ambiguous/unsafe source rejection.
- `service-wireguard-runtime`: A real local peer plus the host and application-namespace tunnels start from runtime private configuration; both routes and namespace DNS reach the peer.

Limitations: Commercial providers, general VPN-server routing/NAT, key rotation, tunnel loss, restart/reboot, encrypted-source loss, runtime autostart and ARM execution are outside this smoke; no archive of runtime interfaces is claimed. No test changes between pinned application revisions.
