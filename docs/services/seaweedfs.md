# SeaweedFS

SeaweedFS provides object and file storage. Nixstead runs a combined local
master, volume, and filer topology under `seaweedfs.service`; their state is
derived from one data root.

## Enable and configure

```nix
nixstead.services.dev.seaweedfs = {
  enable = true;
  domain = "seaweed.home.arpa";
  port = 8888;
  masterPort = 9333;
  paths.dataDir = "/var/lib/seaweedfs";
};
```

`port` is the filer endpoint and `masterPort` is the internal master API; they
must differ. The module derives master, volume, and filer subdirectories from
`paths.dataDir`.

## Credentials and operation

This local topology does not configure application authentication. Restrict it
through the selected exposure policy. Inspect `seaweedfs.service` and its
journal for topology or storage errors.

## Recovery

The registered backup stops the combined process and captures `master`, `volume` and `filer` together. Filer metadata uses the local `leveldb2` store configured by `/etc/seaweedfs/filer.toml`; archives missing any of its eight shard manifests are refused before restoring state. Restore all components with the same package revision and listener configuration. Distributed peers and external metadata databases need a separate recovery policy.

See the [development recovery contracts](../../modules/services/dev/README.md#recovery-ownership)
for ownership boundaries.

The maintained x86_64 fixture checks native startup/readiness and one shipped
Borg backup/restore with an independent test-owned continuity marker. It erases
the declared application root and checks the marker after final readiness.
Business workflows, repeated lifecycle and failure matrices are outside this
smoke fixture. The combined startup/recovery check passed in 109.97 seconds.
Configuration is checked independently on x86_64 and aarch64.
