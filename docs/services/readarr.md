# Readarr

Readarr is [retired upstream](https://github.com/Readarr/Readarr#announcement-retirement-of-readarr).
It is excluded from ARR defaults and all presets. Explicit use remains available
while the pinned package is viable; no migration to another application is
performed. [Shelfmark](shelfmark.md) is an optional acquisition workflow with a
different scope, without library management or background author monitoring.

Readarr manages ebook and audiobook acquisition. Nixstead runs the native
`readarr.service`, sets its listener, and grants shared media-group access.

## Enable and configure

```nix
nixstead.services.arr.readarr = {
  enable = true;
  domain = "readarr.home.arpa";
  port = 8787;
};
```

Configure book roots, download clients, indexers, metadata, and profiles in the
web interface. Keep the download and library paths consistent across services.

## Initial access and credentials

Open `https://readarr.home.arpa`. Nixstead does not generate a Readarr web
password. Configure authentication during first use. The API key in
**Settings > General > Security** can be supplied to Swaparr and Homepage.

Inspect it with `systemctl status readarr` and `journalctl -u readarr`.

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
