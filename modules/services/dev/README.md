# Development stack

This directory contains monitoring, datastore, and developer-facing services:

- Grafana, Prometheus, and Loki;
- Redis, RabbitMQ, PostgreSQL, and MongoDB;
- Forgejo and alternative Gitea;
- pgAdmin, SeaweedFS, Uptime Kuma, and ntfy; and
- shared development tooling/configuration.

```nix
nixstead.services.dev = {
  grafana = {
    enable = true;
    provisioning = {
      enable = true;
      prometheus.enable = true;
      loki.enable = true;
      serviceUsageDashboard.enable = true;
      arrDashboard.enable = true;
      dashboardPaths = [./my-dashboards];
    };
  };
  prometheus = {
    enable = true;
    exporters = {
      node.enable = true;
      systemd.enable = true;
      nginxLog.enable = true;
      cadvisor.enable = true;
    };
  };
  loki = {
    enable = true;
    journal.enable = true;
  };
  postgresql.enable = true;
  forgejo.enable = true;
  ntfy.enable = true;
};
```

The monitoring components are independent. Prometheus can run without any
exporters, exporters can be exposed to an external Prometheus server without
enabling the local server, Loki does not require journal shipping, and Grafana
provisioning is opt-in. The collectors provide:

- `node`: whole-host CPU, memory, disk, and network metrics;
- `systemd`: unit state, CPU, tasks, network accounting, and restart metrics;
- `nginxLog`: request frequency, status, response size, and latency grouped by
  virtual-host domain; and
- `cadvisor`: systemd cgroup and container memory and disk-I/O metrics.

The managed NGINX log intentionally omits client addresses, request paths,
query strings, referrers, and user agents. Set
`prometheus.exporters.nginxLog.configureNginx = false` when feeding the exporter
custom compatible JSON logs instead.

The checked-in **Service Usage & Resources** and **ARR Application Overview**
dashboards are independently opt-in with
`grafana.provisioning.serviceUsageDashboard.enable` and
`grafana.provisioning.arrDashboard.enable`. Grafana-created dashboards remain
in its database, additional dashboard paths can be provisioned with
`grafana.provisioning.dashboardPaths`, and additional data sources can be
appended with `grafana.provisioning.extraDataSources`. Changes made in the UI
to a provisioned dashboard can be saved, but a later change to its source JSON
remains authoritative; duplicate it first when an entirely UI-managed copy is
preferred.

The `development` preset selects curated children directly and leaves the broad
parent off so Gitea is not enabled alongside Forgejo. Several services use the
shared `devdb` secret schema. Optional storage overrides remain under each
service's typed `nixstead.services.dev.<service>.paths` submodule; native defaults are
used when they are unset. SeaweedFS exposes one typed `paths.dataDir` and
derives its internal state directories from that root.

See the [per-service guides](../../../docs/services/README.md) for credentials,
endpoints, storage, and unit-specific troubleshooting.

## Recovery ownership

The service backup command stops each registered writer before copying its state
and restarts the units that were running after staging completes. These policies
use the existing encrypted Borg archive and restore commands. They establish
which state is selected; a passing configuration check is not an application
recovery result. Use the original package revision for initial restoration.

| Service | Snapshot and consistency boundary | Additional recovery requirements |
| --- | --- | --- |
| Grafana | Stop `grafana.service`; archive the effective native `services.grafana.dataDir`, including the default SQLite database, editable dashboards, users and installed plugin data. | Recover the original `devdb/grafana/secretKey` from the separately retained encrypted SOPS source. Replacing it can make saved data-source credentials unusable. Declarative provisioning comes from the repository. External SQL databases, SQLite files moved outside this root and external plugin directories need their own backup owner. |
| RabbitMQ | Stop `rabbitmq.service`; archive the effective native `services.rabbitmq.dataDir`, including `mnesia`, durable messages, account/queue definitions and `.erlang.cookie`. | Restore the same RabbitMQ node name (normally `rabbit@<hostName>`) and compatible package revision. Retain the encrypted bootstrap credentials. This is a single-node policy; coordinated cluster recovery and changing node names are outside it. |
| pgAdmin | Stop `pgadmin.service`; archive `/var/lib/pgadmin`, including its own account/configuration SQLite database, saved server definitions, storage and session state. Restore uses the native dynamic-user directory handling. | Preserve existing login/master passwords and the encrypted bootstrap source so saved connection credentials remain decryptable. The PostgreSQL servers being administered own their separate database backups. Native DATA_DIR/SQLITE_PATH/STORAGE_DIR overrides outside this directory are rejected. External configuration databases and master-password hooks need a separate recovery contract. |
| SeaweedFS | Stop the single `seaweedfs.service` process before copying the configured root containing `master`, `volume` and `filer`. All three directories belong to one snapshot. | Restore all components together, the same listener configuration and package revision. This covers the module's local embedded filer and single-process deployment; remote filer databases and distributed volume peers need their own coordinated policy. |
| PostgreSQL | Follow the effective native `services.postgresql.dataDir`; capture the logical cluster dump while the server runs, then stop it before the physical snapshot. | Restore with the shipped database restore option. Cross-major upgrades require a separately supported migration. |
| MongoDB | Stop `mongodb.service` and copy the effective native `services.mongodb.dbpath`. | Restore the same supported engine revision with the original encrypted root credential. Updating the initial-password source is not an asserted password-rotation mechanism for an existing database. |

Restore encrypted SOPS source through the existing secret-management workflow;
these policies do not archive `/run/secrets` or write decrypted keys into Nix.
Grafana's dedicated x86_64 scenarios restore a usable login, editable dashboard
and saved encrypted datasource credentials, which authenticate to a local query
endpoint after an empty-state Borg restore and reboot. The original encrypted
SOPS key remains an independently retained input. RabbitMQ still needs restored
durable publish/consume and pgAdmin a saved connection that executes a query.
Their populated application recovery remains unverified.
The dedicated SeaweedFS x86_64 VMs passed local filer create/update/delete/list,
independent object byte comparisons across restart/reboot, empty-state Borg
restoration, and missing-filer-shard refusal while preserving healthy objects and
unrelated state. Distributed peers, S3/authentication, arbitrary volume corruption
and pinned cross-version upgrades are outside that verified scope.

The stopped SQLite snapshot follows [Grafana's backup procedure](https://grafana.com/docs/grafana/latest/administration/back-up-grafana/).
RabbitMQ's [disk backup contract](https://www.rabbitmq.com/docs/backup) requires
stopping the node for messages and preserving its node name.
pgAdmin documents its [account database and credential encryption](https://www.pgadmin.org/docs/pgadmin4/9.17/config_py.html)
separately from the databases it administers.
