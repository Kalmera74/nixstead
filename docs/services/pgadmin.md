# pgAdmin

pgAdmin is the web administration interface for PostgreSQL. Nixstead runs the
native `pgadmin.service` and seeds its initial account from the option value and
SOPS password.

## Enable and configure

```nix
nixstead.services.dev.pgadmin = {
  enable = true;
  domain = "pgadmin.home.arpa";
  port = 5050;
  initialEmail = "admin@pgadmin.local";
};
```

Generate the password with `nixstead --host <host> credentials bootstrap devdb`.
Database server registrations made in pgAdmin remain application state.

## Initial credentials

The username is `initialEmail`. The native email validator accepts `.local` so the default `admin@pgadmin.local` can bootstrap. Read the password with:

```bash
sudo cat /run/secrets/devdb/pgadmin/initialPassword
```

Inspect it with `systemctl status pgadmin` and `journalctl -u pgadmin`.

## Recovery

The registered backup stops pgAdmin and captures its own account/configuration database and files under `/var/lib/pgadmin`, using native dynamic-user restoration. Keep the existing login/master passwords and encrypted bootstrap source. DATA_DIR must remain `/var/lib/pgadmin`; SQLITE_PATH and STORAGE_DIR must remain below it. The account SQLite filename is resolved from the effective native setting and required before restore can disrupt the application. External `CONFIG_DATABASE_URI` databases are rejected because this policy cannot snapshot them. PostgreSQL servers managed through this UI have separate database owners and backups.

See the [development recovery contracts](../../modules/services/dev/README.md#recovery-ownership)
for ownership boundaries and unverified application outcomes.


## Service tests

The maintained x86_64 fixture checks native startup/readiness and one shipped
Borg backup/restore with an independent test-owned continuity marker. It erases
the declared application root and checks the marker after final readiness.
Business workflows, repeated lifecycle and failure matrices are outside this
smoke fixture. The combined startup/recovery check passed in 107.53 seconds.
Configuration is checked independently on x86_64 and aarch64.

The pgAdmin SQLite/key directory is restored while managed PostgreSQL databases
remain separately owned. Native internal authentication and the custom SQLite
filename are configured; saved connections and query-tool workflows are outside
the maintained fixture.
