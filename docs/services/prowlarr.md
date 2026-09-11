# Prowlarr

Prowlarr centralizes indexers and synchronizes them to ARR applications.
Nixstead runs the native `prowlarr.service` on the registry-managed endpoint.

## Enable and configure

```nix
nixstead.services.arr.prowlarr = {
  enable = true;
  domain = "prowlarr.home.arpa";
  port = 9696;
};
```

Configure indexers in Prowlarr, then add Sonarr, Radarr, Lidarr, or Readarr under
**Settings > Apps** using each application's URL and API key.

## Initial access and credentials

Open `https://prowlarr.home.arpa`. Nixstead does not generate a Prowlarr login;
finish the application's security setup. Its API key is under
**Settings > General > Security** and can be used by Homepage.

Inspect it with `systemctl status prowlarr` and `journalctl -u prowlarr`.

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
