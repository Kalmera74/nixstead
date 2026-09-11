# Shelfmark

[Shelfmark](https://github.com/calibrain/shelfmark#project-scope) provides book
search, requests and acquisition. It does not manage a library or continuously
monitor authors/releases. It does not translate Readarr configuration.

```nix
nixstead.services.arr.shelfmark = {
  enable = true;
  paths.ingestDir = "/data/ingest/books";
  integrations.enable = true;
};
```

The explicit ingest destination is required. Select `arr.storage.manageDirectories`
to create it, or prepare and validate it separately. Shared media-group access,
mount guards and disposable permission probes apply. The native service uses
private dynamic-user state at `/var/lib/shelfmark`, backed up under `shelfmark`.

The registry provides optional setup selection, proxy, Homepage card and health
unit. Shelfmark is excluded from presets. Complete administrator setup before
exposing it: a fresh upstream instance permits setup until an administrator
exists, even when `AUTH_METHOD=builtin` is selected.

Eligible Prowlarr and qBittorrent connection defaults use direct internal URLs and
per-consumer runtime credentials. Each can be disabled using
`integrations.prowlarr=false` or `integrations.qbittorrent=false`. The downloader
password comes from the canonical `qbittorrent/password` SOPS entry shared with ARR. Prowlarr key rotation
restarts Shelfmark. These are supported upstream startup defaults; settings saved
in Shelfmark's UI can override them. Its native connection-test APIs are covered
by local runtime tests. Select metadata providers, sources and library ingestion
behavior explicitly in Shelfmark; no external indexers are provisioned.

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
