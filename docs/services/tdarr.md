# Tdarr server and node

Tdarr scans media and runs configurable transcoding or health-check flows.
Nixstead can enable the server, a local processing node, or both. The server
owns the web UI and node API; the local node shares the configured media path.

## Enable and configure

```nix
nixstead.services.media.tdarr = {
  enable = true;
  server = true;
  node = true;
  port = 8265;
  serverPort = 8266;
  paths = {
    cacheDir = "/mnt/appdata/selfhosted/tdarr/cache";
    dataDir = "/var/lib/tdarr";
    mediaDir = "/mnt/media";
  };
};
```

`port` and `serverPort` must differ. `paths.dataDir` is optional and otherwise
uses the NixOS default. Configure each library to use `paths.cacheDir` as its
transcode cache; the directory is mounted and made writable to both the server
and local node. `paths.mediaDir` must be writable when Tdarr replaces files.
Configure libraries, flows, plugins, and GPU encoders in the UI at
`https://tdarr.home.arpa`.

## Credentials and operation

This configuration does not provision Tdarr authentication or an initial
password. Inspect `tdarr-server.service` and `tdarr-node-local.service`.

Tdarr defaults to its dedicated `tdarr` account and the shared media group;
enabling it does not require a managed personal user. To preserve a previous
installation that ran as the host user, explicitly set
`services.tdarr.user = "existing-media-owner";` and keep that account declared
in `users.users`. Changing identities requires a separate review of access to
existing state, media, and cache directories. Keep any compatibility identity
override in the consumer host configuration rather than the shared framework.

## Recovery boundary

The server owns `${services.tdarr.dataDir}/server`: its configuration, databases,
library/plugin/flow definitions and job records. The Borg policy stops the server
before copying this entire native root and restores its configured user/group.
A backup missing `configs/Tdarr_Server_Config.json` is refused. The sibling
`nodes/` directories, external transcode cache and source media are outside this
archive. Pause/drain active transcodes before recovery; this policy does not
promise resumption of a partially written output file or replacement of an
original from a different point in time.

Source media and accepted transcode outputs belong to the storage owner and need
an independent backup. The node reconstructs its disposable runtime/cache;
remote nodes must reconnect after server restoration. If authentication uses a
native `environmentFile`, retain its encrypted source and keys independently.

The configuration suite verifies native paths, identity, quiescing and required
configuration. The focused x86_64 smoke starts the native server and local node
with workers paused, checks the server HTTP endpoint, and restores an independent
server-root marker through one clean encrypted Borg backup/restore. It does not
exercise transcodes, populated libraries, detailed node reconnection, source
bytes, repeated reboots or ARM runtime. The pinned NixOS module's `rootDataPath` and working
directory establish the server root; [Tdarr's volume mapping](https://docs.tdarr.io/docs/installation/docker/volume-mapping/)
distinguishes server/configuration state from media and transcode cache.

The native Tdarr 2.86.01 server/local-node smoke passed on x86_64 in 75.20
seconds, including one clean server-root Borg restore. Configuration checks
build on x86_64 and strictly evaluate on aarch64. Optional internet plugin
updates are outside this offline fixture.
