# Prometheus

Prometheus collects and queries time-series metrics. Nixstead creates a local
Prometheus scrape plus optional node, systemd, NGINX-log, and cAdvisor exporter
jobs. Extra scrape jobs can be appended without replacing generated jobs.

## Enable and configure

```nix
nixstead.services.dev.prometheus = {
  enable = true;
  domain = "prometheus.home.arpa";
  port = 9091;
  scrapeInterval = "15s";
  exporters = {
    node.enable = true;
    systemd.enable = true;
    nginxLog.enable = true;
    cadvisor.enable = true;
  };
};
```

Each exporter has `listenAddress`, `port`, and `openFirewall`; keep exporters on
loopback unless another host must scrape them. `paths.stateDir` may relocate
Prometheus below `/var/lib`. Use `extraScrapeConfigs` for other targets.

## Credentials and operation

The generated Prometheus endpoint has no authentication. Open
`https://prometheus.home.arpa`, or use it through Grafana. Check targets under
**Status > Targets** and inspect `prometheus.service` plus the relevant exporter
unit when a job is down.

## History, retention and loss

Nixstead treats local Prometheus history as disposable and does not include it
in the service Borg archive. TSDB blocks and the WAL live below the effective
native state directory (`/var/lib/prometheus2` by default). Restart and reboot
should preserve that history; deleting the directory intentionally loses it.
After a stopped instance's state is discarded, the native unit recreates its
directory and collects new samples from its configured targets. Earlier values
cannot be reconstructed by scraping the current target value.

Choose a retention period and storage budget for the host. For example:

```nix
services.prometheus.retentionTime = "24h";
```

When no duration or size limit is selected, Prometheus uses its
[upstream 15-day default](https://prometheus.io/docs/prometheus/latest/configuration/configuration/).
This setting limits local history; it is not a backup policy. A host that must
retain history independently needs a separately owned storage/backup design.

The maintained scenario starts actual Prometheus and the native node exporter,
checks the configured loopback listener and waits for Prometheus readiness. It
does not retain or back up local history. Scraping semantics, history across
restart/reboot, target failures, retention expiry, remote storage, upgrades and
ARM execution remain unverified by this fast smoke. See the
[support matrix](../support-matrix.md) for execution evidence.

The bounded Prometheus startup check passed on x86_64-linux in 23.01 seconds.
