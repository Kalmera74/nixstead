# Sonarr

Sonarr is the TV-series manager in the ARR stack. Nixstead runs the native
NixOS `sonarr.service`, binds it according to the selected exposure policy, and
adds the service account to the shared media group.

## Enable and configure

```nix
nixstead.services.arr.sonarr = {
  enable = true;
  domain = "sonarr.home.arpa";
  port = 8989;
};
```

The option path is `nixstead.services.arr.sonarr`; the ARR parent can enable it by
default. Library roots, download clients, indexers, quality profiles, and
authentication are configured in Sonarr's web interface. Use paths accessible
to the media group.

## Initial access and credentials

Open `https://sonarr.home.arpa`. Nixstead does not generate a Sonarr login;
complete the application's first-run security configuration. Its API key is in
**Settings > General > Security** and is needed by integrations such as
Prowlarr, Swaparr, and the optional Homepage widget.

Inspect it with `systemctl status sonarr` and `journalctl -u sonarr`.

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

Sonarr retains the established `/var/lib/sonarr` archive layout, including its
native `.config/NzbDrone` subtree. A custom native `services.sonarr.dataDir` is
not covered by this backup fixture.
