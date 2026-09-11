# Loki

Loki stores and queries logs. Nixstead runs the native `loki.service`; when the
journal pipeline is enabled, Grafana Alloy reads the systemd journal, attaches
unit/priority/identifier labels, and pushes records to Loki.

## Enable and configure

```nix
nixstead.services.dev.loki = {
  enable = true;
  domain = "loki.home.arpa";
  port = 3100;
  journal = {
    enable = true;
    maxAge = "12h";
  };
};
```

`paths.dataDir` relocates Loki state. `journal.endpoint` can target an external
Loki push endpoint, and `journal.extraConfig` appends Alloy configuration.

This module runs Loki as a single process. Its internal gRPC listener, ring
advertisement and frontend return address all use `127.0.0.1`, independently of
HTTP exposure. This prevents the default interface discovery from advertising a
LAN address that a loopback listener cannot serve. See the
[Loki configuration reference](https://grafana.com/docs/loki/latest/configure/).

Alloy applies the unit, severity and syslog-identifier rules at the journal
source, before internal journal labels are discarded. Passing records through
a later relabel receiver loses those fields; see the
[journal source reference](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/).

## Access and credentials

Loki exposes an API, not a full standalone web UI, and this configuration does
not add authentication. Use **Explore** in Grafana with the provisioned Loki
datasource. Inspect `loki.service` and `alloy.service`; API readiness is at
`/ready`.

## History, retention and loss

Nixstead treats local Loki history as disposable and does not include it in the
service Borg archive. The effective native data directory owns the local WAL,
indexes and filesystem chunks. Restart and reboot should preserve the history.
Deleting the directory intentionally loses it; recreate the empty directory
with the configured Loki user/group and resume ingestion. Producers are not
required to replay historical records, and restarting Alloy does not establish
recovery of records whose journal retention has already elapsed.

The wrapper leaves automatic retention deletion disabled by default. Select an
appropriate retention period and storage budget for the host; local filesystem
storage does not evict chunks merely because the disk is filling. A local
24-hour profile can be configured as follows:

```nix
services.loki.configuration = {
  limits_config.retention_period = "24h";
  compactor = {
    retention_enabled = true;
    delete_request_store = "filesystem";
    working_directory = "/var/lib/loki/retention";
  };
};
```

Keep the working directory inside the effective data directory when relocating
storage. The wrapper's 24-hour index period supports the
[native retention policy](https://grafana.com/docs/loki/latest/operations/storage/retention/).
A host requiring independent historical recovery needs its own complete
storage policy, including indexes and log bytes.

The maintained single-process scenario starts actual Loki, checks the configured
loopback listener and waits for `/ready`. It does not retain or back up local
history. Log ingestion/query behavior, history across restart/reboot, retention
expiry, external object storage, distributed operation, upgrades and ARM
execution remain unverified by this fast smoke. See the
[support matrix](../support-matrix.md) for execution evidence.

The bounded Loki startup check passed on x86_64-linux in 48.11 seconds.
Configuration assertions pass for x86_64-linux and aarch64-linux.
