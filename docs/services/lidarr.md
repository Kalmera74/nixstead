# Lidarr

Lidarr manages music libraries and downloads. It runs as the native
`lidarr.service` and receives membership in the shared media group.

## Enable and configure

```nix
nixstead.services.arr.lidarr = {
  enable = true;
  domain = "lidarr.home.arpa";
  port = 8686;
};
```

Artists, library roots, download clients, indexers, metadata profiles, and
authentication remain application settings. Use a library root writable by the
media group and path mappings consistent with qBittorrent.

## Initial access and credentials

Open `https://lidarr.home.arpa`. Nixstead does not preseed a web login. Create
the desired authentication configuration on first use. The API key under
**Settings > General > Security** is used by Swaparr and Homepage integrations.

Inspect it with `systemctl status lidarr` and `journalctl -u lidarr`.

## Optional operational integration

See [media operations](../media-operations.md) for runtime credential sharing,
selected API relationships and storage permissions, and the
[support matrix](../support-matrix.md) for tested behavior. These features require
explicit selection; enabling a service alone does not perform API reconciliation.

## Dedicated smoke checks

The x86_64 service checks share one combined native ARR startup/recovery
fixture, so selecting several family members reuses one VM derivation.
They check service readiness, private runtime SOPS credentials, and one selected
shipped reconciliation. Stateful services get one encrypted Borg backup and
empty-state restore, followed by readiness and an independent file marker in
each selected metadata root. Media acquisition/import, existing queues and
libraries, repeated lifecycle, and incomplete-input matrices are outside this
fixture. Source and download bytes remain separately owned.

The combined x86_64 startup/recovery check passed in 641.19 seconds in the
recorded run. Configuration is checked independently for each service on x86_64
and aarch64.

Lidarr retains the established `/var/lib/lidarr` archive layout, including its
native `.config/Lidarr` subtree. A custom native `services.lidarr.dataDir` is
not covered by this backup fixture.
