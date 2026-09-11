# Bazarr

Bazarr downloads and manages subtitles for Sonarr and Radarr libraries.
Nixstead runs `bazarr.service` and grants it shared media-group access.

## Enable and configure

```nix
nixstead.services.arr.bazarr = {
  enable = true;
  domain = "bazarr.home.arpa";
  port = 6767;
};
```

After opening `https://bazarr.home.arpa`, connect Bazarr to Sonarr and Radarr
with their internal URLs and API keys, then configure subtitle languages and
providers. Provider credentials are application data and are not stored in the
Nix modules.

## Initial access and credentials

Nixstead does not preseed a Bazarr login. Configure authentication in Bazarr
if required. Bazarr's own API key is available from its general settings for
the optional Homepage widget.

Inspect it with `systemctl status bazarr` and `journalctl -u bazarr`.

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
