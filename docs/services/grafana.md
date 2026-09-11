# Grafana

Grafana is the web interface for dashboards, metrics, and log exploration.
Nixstead runs the native `grafana.service` and can provision Prometheus, Loki,
independently selected built-in dashboards, and additional dashboards
declaratively.

## Enable and configure

```nix
nixstead.services.dev.grafana = {
  enable = true;
  domain = "grafana.home.arpa";
  port = 3001;
  provisioning = {
    enable = true;
    prometheus.enable = true;
    loki.enable = true;
    serviceUsageDashboard.enable = true;
    arrDashboard.enable = true;
    dashboardPaths = [./dashboards];
  };
};
```

`serviceUsageDashboard.enable` provisions host, HTTP, and systemd resource
statistics. `arrDashboard.enable` provisions application statistics from the
ARR exporters scraped by Prometheus. Both default to false and are independent:
Grafana can run with neither built-in dashboard, or a host can enable either or
both. `paths.dataDir` optionally relocates Grafana state. Provisioned dashboards
are repository-owned defaults; dashboards created or copied in the UI remain
editable application state.

## Initial credentials

Grafana uses the SOPS `devdb` branch. Read the initial login only on the host:

```bash
sudo cat /run/secrets/devdb/grafana/adminUser
sudo cat /run/secrets/devdb/grafana/adminPassword
```

Inspect it with `systemctl status grafana` and `journalctl -u grafana`.

## Recovery

The registered backup stops Grafana and captures its native data directory,
including the default SQLite database at `data/grafana.db` beneath that root.
Restore refuses an archive missing that database before changing application
state. This policy follows a custom `paths.dataDir` and requires the native
SQLite layout. An external SQL database, independently relocated SQLite file or
external plugin directory needs its own recovery policy and backup owner.

Keep the original encrypted SOPS `devdb/grafana/secretKey` source and decryption
identity separately. Restored dashboards can coexist with unusable saved
data-source credentials if that key changes. The application archive does not
contain `/run/secrets` or replace the encrypted configuration source.

The maintained x86_64 fixture checks native startup/readiness and one shipped
Borg backup/restore with an independent test-owned continuity marker. It erases
the declared application root and checks the marker after final readiness.
Business workflows, repeated lifecycle and failure matrices are outside this
smoke fixture. The combined startup/recovery check passed in 111.17 seconds.
Configuration is checked independently on x86_64 and aarch64.

Run the focused suites with:

```bash
nix build --no-link -L path:.#checks.x86_64-linux.service-grafana
```

Extra plugins, external databases, encryption key rotation/loss and cross-version
upgrades remain unverified profiles. ARM currently has configuration checks only.

See the [development recovery contracts](../../modules/services/dev/README.md#recovery-ownership)
for the surrounding services' ownership boundaries.
