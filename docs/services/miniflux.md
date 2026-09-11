# Miniflux

Miniflux is a minimal RSS reader. Nixstead runs the native service with a local
PostgreSQL database and creates a persistent random administrator password
before first startup.

## Enable and configure

```nix
nixstead.services.productivity.miniflux = {
  enable = true;
  domain = "reader.home.arpa";
  port = 8190;
};
```

The fixed state directory `/var/lib/miniflux` contains the bootstrap environment
file. Feeds, refresh intervals, integrations, and additional users are managed
inside Miniflux.

## Initial credentials

Retrieve the generated or configured username and password with:

```bash
sudo nixstead --host <host> credentials show miniflux
```

Set `adminCredentialsFile` to a SOPS template containing `ADMIN_USERNAME` and
`ADMIN_PASSWORD` to choose both values before activation. When unset, the
existing `/var/lib/miniflux/admin.env` fallback is generated. See
[Secrets and credentials](../secrets.md#find-and-retrieve-credentials).

Inspect `miniflux-bootstrap-credentials.service` and `miniflux.service`.

## Database and recovery

Miniflux's connection, database bootstrap and backup tools follow
`services.postgresql.settings.port`, including a custom local PostgreSQL port.
The application uses the local Unix socket and owns the `miniflux` database and
role. The administrator login is an application account stored in that database;
it is separate from the PostgreSQL peer-authenticated service role.

The recovery policy stops Miniflux while saving `/var/lib/miniflux` and a scoped
PostgreSQL dump. Restore both with the shipped restore command and its
`--restore-databases` flag. The default bootstrap credential file is part of the
saved directory. A configured SOPS `adminCredentialsFile` remains owned by the
encrypted configuration and its decryption identity; preserve those separately.
The scoped database backup assumes the PostgreSQL server and `miniflux` role
exist. It does not replace a full-cluster recovery procedure.

The maintained x86_64 fixture checks native startup/readiness and one shipped
Borg backup/restore with independent test-owned SQL and file markers. It erases
the application directory and drops its scoped PostgreSQL database, then checks
both markers after final readiness.
Business workflows, repeated lifecycle and failure matrices are outside this
smoke fixture. The combined startup/recovery check passed in 45.44 seconds.
Configuration is checked independently on x86_64 and aarch64.

Run the focused suites with:

```bash
nix build --no-link -L path:.#checks.x86_64-linux.service-miniflux
```

Feed workflows, quoted SOPS credential overrides, publisher/database outages,
full-cluster loss and cross-version upgrades remain unverified by this smoke.
