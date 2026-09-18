# Support and verification

Support levels describe specific automated evidence, not a guarantee for every
host, filesystem, package override or external provider. Automatic CI evaluates
representative configurations on x86_64-linux. The manual heavy workflow checks
the full public module API on x86_64-linux and aarch64-linux. Runtime groups
currently run on x86_64-linux; ARM runtime behavior is not claimed.

The [service coverage catalogue](generated/test-coverage.md) lists every registry
entry and its independently runnable checks. All 66 entries now have dedicated
configuration suites; runtime and recovery coverage remains partial. A declared
scenario is not a recorded pass or a full-support
claim. The maintained baseline now favors quick native startup/readiness checks
and one clean backup/restore for owned state. Detailed application workflows,
failure matrices, repeated restarts and reboots are outside that baseline. See
[suite authoring and execution](../tests/README.md).

## Current bounded service baseline

All runtime and recovery checks in this section ran on disposable x86_64 KVM
guests. A combined recovery check performs the real initial startup/readiness
check, creates one small independent marker, makes one encrypted service backup,
erases owned storage, restores once through Borg and verifies readiness plus the marker. It
does not run a second runtime VM for the same stateful profile.

| Group | Passing current evidence | Boundary |
| --- | --- | --- |
| Configuration | All 66 dedicated service reports on x86_64-linux and aarch64-linux | Native module construction and applicable enable/disable, option, listener, exposure, proxy/card, credential and backup wiring; no ARM runtime claim |
| ARR | One shared combined check for ARR reconciliation state, Sonarr, Radarr, Lidarr, Readarr, Bazarr, Prowlarr, qBittorrent, SABnzbd and Shelfmark; the same fixture establishes Swaparr startup | No media acquisition, queue/library or source-byte recovery workflow |
| Media | Combined checks for Jellyfin, Seerr, Tdarr, Komga, Kavita, Audiobookshelf, Immich, RomM and TubeArchivist; runtime-only Kiwix and shared Tdarr-node startup | Application readiness and owned state only; source media and libraries retain separate owners |
| Development | Combined checks for PostgreSQL, MongoDB, Redis, RabbitMQ, Grafana, Forgejo, Gitea, pgAdmin, SeaweedFS, Uptime Kuma and ntfy; runtime-only Prometheus and Loki | Prometheus/Loki local history is disposable in the current policy |
| Productivity | Combined checks for Paperless, Nextcloud, n8n, Seafile, Wallabag, Linkwarden, Mealie, Actual Budget default/custom storage, Miniflux and SearXNG; runtime-only Stirling PDF | No business workflows or external provider compatibility |
| Standalone and local AI | Combined checks for Vaultwarden, Home Assistant, Authentik, Syncthing, Scrutiny and Open WebUI; runtime-only Ollama and llama.cpp | Synced/source files and unique model inputs keep their documented external ownership boundaries |
| Platform and external adapters | Runtime-only Homepage/TrueNAS, nginx, Tailscale, WireGuard, CIFS, NAS, Samba, Pi-hole and Proxmox checks | Bounded local peers only; no appliance, enrolled-identity, local-CA, Samba-account or aggregate storage recovery claim |

This yields startup evidence for 64 of 66 entries and clean service-recovery
evidence for 46 of 54 stateful entries. SnapOtter startup/restore remains
unverified because its exact image has about 3.56 GiB of compressed layers;
stable-diffusion.cpp lacks a suitably small complete checkpoint fixture. The
other recovery gaps are the explicitly disposable, externally owned or
policy-less state described in the
[implementation status](service-test-implementation-status.md). The generated
runtime CI selector reduces 65 dedicated service check names to 53 unique CI
executions.

## Recorded bounded execution results

These results use the current configuration, startup and single-restore scope.
The service guides describe the selected state and ownership boundaries.

| Profile | Configuration | Executed result | Scope and limits |
| --- | --- | --- | --- |
| Shared WireGuard startup | `service-wireguard-config` on both architectures; public standalone module and source/namespace validation | `service-wireguard-runtime` smoke passed in 32.04s on x86_64-linux | Disposable local peers, a native host tunnel and an attached namespace service start, and their configured routes and DNS reach the peer. Key rotation, tunnel loss, restart/reboot, commercial-provider compatibility, VPN-server policy, runtime-state archives and ARM execution remain unverified |
| MongoDB startup and WiredTiger restore | `service-mongodb-config` on both architectures, including effective native port/path | Recovery smoke passed in 226.36s on x86_64-linux | Native MongoDB starts with a runtime-generated root credential and stores one exact marker document; one encrypted stopped-WiredTiger backup and clean Borg restore recovers the erased directory, readiness and marker. Account/role workflows, credential rotation, failure matrices, replica sets, sharding, ARM runtime and upgrades remain unverified |
| nginx proxy startup | `service-nginx-config` on both architectures | Runtime smoke passed in 38.62s on x86_64-linux | Native nginx, its generated local CA and a registry proxy start; an independent client reaches the proxy over trusted HTTPS while direct access to the loopback backend fails. CA archive recovery, rotation/retrust, repeated lifecycle, upstream failures, WebSockets, external CAs and ARM runtime remain unverified |
| SearXNG startup and server-identity restore | `service-searxng-config` on both architectures | Combined startup/recovery smoke passed in 49.46s on x86_64-linux | Native SearXNG reaches its configured loopback endpoint with one bounded local query; one encrypted backup and clean Borg restore recovers the generated server secret and returns the service to readiness. Public-engine compatibility, ranking, limiter behavior, browser UI, ARM runtime and upgrades remain unverified |
| Prometheus startup | `service-prometheus-config` on both architectures | Runtime smoke passed in 23.01s on x86_64-linux | Native Prometheus and its node exporter start, the configured loopback listener opens and `/-/ready` succeeds. Metrics workflows, history, retention, remote storage, ARM runtime and upgrades remain unverified |
| Loki startup | `service-loki-config` on both architectures | Runtime smoke passed in 48.11s on x86_64-linux | Native Loki starts, the configured loopback listener opens and `/ready` succeeds. Ingestion/query workflows, history, retention, external storage, ARM runtime and upgrades remain unverified |
| llama.cpp startup | `service-llamacpp-config` on both architectures | Runtime smoke passed in 39.93s on x86_64-linux | Native server starts with an immutable licensed 19 MB GGUF and serves its loopback health endpoint. Inference semantics, restart/reboot, large models, GPU/ARM execution, unique-asset backup and upgrades remain unverified |
| Ollama startup | `service-ollama-config`, including standalone shared-group creation | Runtime smoke passed in 30.00s on x86_64-linux | Native Ollama starts with its configured model directory and serves its loopback version endpoint. Model import/inference/persistence, restart/reboot, unique-model recovery, GPU/ARM execution and upgrades remain unverified |
| Authenticated CIFS client startup | `service-cifs-config` on both architectures | Runtime smoke passed in 39.01s on x86_64-linux | A native Samba peer and the actual CIFS automounts start with runtime credentials, and the client reads exact bytes from both shares. Rotation, outage/reconnect, reboot, server-byte recovery and ARM runtime remain unverified |
| Local mergerfs and SnapRAID startup | `service-nas-config` on both architectures | Runtime smoke passed in 30.38s on x86_64-linux | Three disposable ext4 filesystems and mergerfs start, and one bounded writer stores and reads an exact pool marker. SnapRAID sync/scrub/repair, missing mounts, restart/reboot and independent archive recovery remain unverified |
| Homepage and TrueNAS adapter startup | `service-homepage-config` and `service-truenas-config` on both architectures | Runtime smoke passed in 39.51s as one shared x86_64-linux derivation | Native Homepage and a bounded TrueNAS peer start, the dashboard becomes ready and one authenticated widget response succeeds. Rotation, dependency failures, restart/reboot, live-appliance compatibility and ARM runtime remain unverified |
| Proxmox remote adapter startup | `service-proxmox-config` on both architectures | Runtime smoke passed in 41.86s on x86_64-linux | Native Homepage and a bounded self-signed HTTPS Proxmox peer start, and one SOPS-backed resource response succeeds. Rotation, dependency failures, restart/reboot, live-version compatibility, guest recovery and ARM runtime remain unverified |
| Pi-hole DNS adapter startup | `service-pihole-config` on both architectures, including explicit default-off mutation | Runtime smoke passed in 28.04s on x86_64-linux on 2026-09-18 (user-supplied execution log) | The shipped opt-in sync starts, authenticates to a bounded Pi-hole v6 API peer and applies the configured owned records once while preserving unrelated records with multiple hostnames. Idempotence, credential rotation, failure handling, reboot, live-version compatibility, appliance recovery, DNS queries and ARM runtime remain unverified |
| Kiwix generated catalogue startup | `service-kiwix-config` passed on both architectures | Runtime smoke passed in 29.11s on x86_64-linux | Native Kiwix generates a valid empty catalogue, completes its refresh oneshot and serves the configured loopback endpoint without a retry. Archive browsing/search and ARM runtime remain unverified; source ZIMs are externally owned and no archive backup applies |
| Stirling PDF startup | `service-stirlingpdf-config` on both architectures | Runtime smoke passed in 137.39s on x86_64-linux | Native service starts without a systemd retry and serves its configured loopback endpoint. The supported profile disables authentication and retained settings, so no backup applies; document operations and upgrades remain unverified |
| Komga startup and application-state restore | `service-komga-config` on both architectures | Combined startup/recovery smoke passed in 247.44s on x86_64-linux | Native service initializes SQLite and serves its readiness API; one encrypted backup and clean Borg restore recovers empty application storage and an exact continuity marker. Accounts and library/reader workflows remain unverified; source books are externally owned |
| Wallabag startup and application-state restore | `service-wallabag-config` on both architectures | Combined startup/recovery smoke passed in 207.80s on x86_64-linux | Wallabag, MariaDB and Redis start from their exact pinned images and serve the configured loopback endpoint; one encrypted backup and clean Borg restore recovers MariaDB, application files and an exact continuity marker. Redis is a disposable cache; saved-page workflows and ARM runtime remain unverified |
| Samba startup and selected-share access | `service-samba-config` on both architectures | `service-samba-runtime` smoke passed in 30.74s on x86_64-linux | Native Samba starts; an authenticated client writes and reads exact bytes through one selected share, while the configured read-only share rejects a write. Account/share recovery, rotation, missing storage, restart/reboot and ARM runtime remain unverified |

A successful evaluation checks test construction, not execution. Local results
do not establish a successful remote CI run. Cross-version upgrades, manual
[installation trials](installation-trial.md), external-provider compatibility
and ARM runtime remain unverified. A restore claim covers the selected state
and continuity marker, not every application feature.

See [development checks](validation.md), the
[generated service catalogue](generated/services.md), and the
[implementation status](service-test-implementation-status.md).

User-supplied execution logs from 2026-09-18 also record 25 passing targeted
Python tests: 13 setup/preflight, 5 backup archive naming/selection, and 7 host
selection tests. Setup identity propagation and backup selection use mocked
commands; these results do not establish a fresh installation or real Borg
pruning across multiple hosts.
