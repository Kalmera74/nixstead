# Swaparr

Swaparr is a headless cleanup worker that removes stalled downloads reported by
enabled ARR applications. It has no web UI. Nixstead starts one hardened Docker
container per enabled Sonarr, Radarr, Lidarr, or Readarr child.

## Enable and configure

```nix
nixstead.services.arr.swaparr.enable = true;
```

Each worker connects to its application on loopback, scans every ten minutes,
and uses the repository defaults for strike count, maximum download time, and
removal behavior. The current module does not expose those worker settings as
typed host options.

## Credentials and operation

Swaparr uses the canonical Sonarr/Radarr/Lidarr SOPS keys shared with other
consumers. Readarr retains its manually supplied `swaparr/readarrApiKey`.
Supported application keys are enrolled into SOPS automatically before startup
and shared through restricted runtime files. Encrypted key changes refresh the
affected workers automatically. See [credential operations](../media-operations.md#canonical-sops-credentials).

Inspect a worker with `systemctl status docker-swaparr-radarr` or the matching
application suffix. There are no initial login credentials.

## Optional operational integration

See [media operations](../media-operations.md) for runtime credential sharing,
selected API relationships and storage permissions, and the
[support matrix](../support-matrix.md) for tested behavior. These features require
explicit selection; enabling a service alone does not perform API reconciliation.

## Dedicated smoke checks

The shared ARR fixture starts the exact pinned worker image against
native Sonarr, Radarr, Lidarr and Readarr, with runtime SOPS API keys and dry-run
mode. It checks each worker's native healthy value. This checks startup wiring;
download decisions, removals, retries and failure behavior remain outside the
fixture. Swaparr owns no durable state and has no application archive.

The worker checks reuse the family's combined startup/recovery VM so selecting
the whole family does not launch duplicate guests. Peer application backup and
restore activity does not establish Swaparr recovery; its worker state is
reconstructable. The combined x86_64 check passed in 641.19 seconds in the recorded run. Configuration is checked
independently on x86_64 and aarch64.
