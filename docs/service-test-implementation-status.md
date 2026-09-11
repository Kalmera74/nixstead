# Service test implementation status

The maintained service-test baseline is now intentionally narrow:

- evaluate every service configuration on both supported architectures;
- start the real configured service and wait for a bounded readiness signal;
- for owned durable state with a shipped service backup, create one small
  independent marker, make one encrypted backup, erase the owned storage,
  restore once through Borg, and verify readiness plus the original marker.

Application business workflows, broad failure matrices, repeated restarts,
reboots and cross-version upgrades are outside this baseline.

## Current coverage

| Contract | Current result |
| --- | --- |
| Dedicated service descriptors | 66 of 66 |
| Configuration | 66 of 66 on x86_64-linux and aarch64-linux |
| Startup/readiness | 64 of 66 on x86_64-linux KVM |
| Clean backup/restore | 46 of 54 stateful entries on x86_64-linux KVM |
| Runtime CI selection | 65 service check names collapse to 53 unique executions and at most 8 heavy runner jobs |
| ARM runtime | No runtime claim; configuration evaluation only |

Every stateful service recovery descriptor uses the same VM to establish its
initial startup and its restore. There is no separate runtime VM for the same
profile. Services that share one fixture, including ARR, Homepage/TrueNAS
and Tdarr server/node, also share one CI execution key.

PRs and main-branch pushes do not run service VMs. Manually dispatched heavy
runs can select the full set, seven canaries or one registry service. Full runs
pack the suite into at most eight weighted shards, so each runner executes
several isolated service VMs sequentially and reuses its Nix store.

## Executed service evidence

The following combined startup/restore checks have passed on x86_64 KVM:

- ARR: ARR reconciliation state, Sonarr, Radarr, Lidarr, Readarr, Bazarr,
  Prowlarr, qBittorrent, SABnzbd and Shelfmark in one grouped VM.
- Media: Jellyfin, Seerr, Tdarr server, Komga, Kavita, Audiobookshelf, Immich,
  RomM and TubeArchivist.
- Development: PostgreSQL, MongoDB, Redis, RabbitMQ, Grafana, Forgejo, Gitea,
  pgAdmin, SeaweedFS, Uptime Kuma and ntfy.
- Productivity: Paperless, Nextcloud, n8n, Seafile, Wallabag, Linkwarden,
  Mealie, Actual Budget in its default and custom storage profiles, Miniflux
  and SearXNG.
- Standalone: Vaultwarden, Home Assistant, Authentik, Syncthing and Scrutiny.
- Local AI: Open WebUI.

Runtime-only startup checks have passed for Swaparr, Tdarr node, Kiwix,
Prometheus, Loki, Ollama, llama.cpp, Stirling PDF, Homepage, nginx, Tailscale,
WireGuard, CIFS, NAS, Samba, Pi-hole, Proxmox and TrueNAS. Shared fixtures do
not turn disposable worker state or externally owned data into recovery claims.

The unchanged nixpkgs revision is
`dc5d91f840324650bac8c379428c7037a416959a`. Service guides record the exact
profile, fixture limits and observed timings. All execution used disposable
test systems; no development-host rebuild, switch or activation was performed.

## Explicit gaps

Two entries have configuration coverage without a maintained startup VM:

- SnapOtter's exact supported amd64 application image contains about 3.56 GiB
  of compressed layers, which is disproportionate to this fast smoke baseline.
- stable-diffusion.cpp needs a complete compatible checkpoint before its server
  listens; no suitably small maintained fixture is available.

Eight stateful entries have no maintained service recovery check:

- Prometheus and Loki treat local history as disposable.
- NAS data belongs to the selected storage owner rather than the aggregate
  mount module.
- nginx local-CA continuity, Tailscale enrolled identity, Samba account state
  and unique Ollama model assets do not yet have shipped recovery policies.
- SnapOtter remains blocked by the image-size constraint above.

These remain visible as missing coverage in the
[generated catalogue](generated/test-coverage.md). Configuration, startup and
restore evidence does not claim business semantics, external-provider
compatibility, hardware profiles, ARM execution or upgrade compatibility.

## Validation

The integrated source is checked with the packaged Python suite, Ruff,
ShellCheck, Bash syntax checks, Alejandra, catalogue validation, generated
document drift checks, both architecture configuration aggregates, the public
module API check and flake evaluation of every maintained service suite. Runtime
checks remain independently selectable so ordinary changes run only affected
unique fixtures.

No Git commit was created.
