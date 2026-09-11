# Vaultwarden

Vaultwarden is a lightweight Bitwarden-compatible password server. Nixstead
runs the native `vaultwarden.service`, enables WebSocket proxying, disables
public signup, and supplies the administration token from SOPS.

## Enable and configure

```nix
nixstead.services.vaultwarden = {
  enable = true;
  domain = "vaultwarden.home.arpa";
  port = 8222;
  paths.backupDir = "/var/backup/vaultwarden";
};
```

`paths.backupDir` is optional; native backups remain disabled when it is null.
Generate the administration token with
`nixstead --host <host> credentials bootstrap vaultwarden`.

The `backup-vaultwarden.timer` runs the native backup daily at 23:00, configured
by `nixstead.services.vaultwarden.backup.schedule`. The job
requires the backup mount, snapshots SQLite (including committed WAL data) into
a private local runtime directory, and checks database integrity before copying
to the backup directory. It verifies the copied bytes and renames the new
database into place only after success. SQLite and copy failures fail the unit
and preserve the previous database backup. This avoids SQLite locking on CIFS.
The password server does not require the backup mount to start.
The destination is created with mode `0700` after its mount is available;
snapshot jobs run only through their timer or an explicit start.
Attachments, sends and keys are copied separately; this is not an atomic
snapshot of the entire vault. General Borg backups have their own opt-in policy.

After activation, run and inspect a backup:

```bash
sudo systemctl start backup-vaultwarden.service
systemctl status backup-vaultwarden.service
journalctl -u backup-vaultwarden.service -n 30 --no-pager
```

An older zero-byte `db.sqlite3` is not a recovery point; a successful run of the
fixed job replaces it with a validated snapshot.

For a private root-owned local or network backup destination, configure the
existing accounts and schedule directly:

```nix
nixstead.services.vaultwarden = {
  paths.backupDir = "/mnt/private-backups/vaultwarden";
  backup = {
    user = "root";
    group = "root";
    schedule = "Sun 02:00";
  };
};
```

Declare the filesystem mount normally. The shared module supplies mount
dependencies and directory preparation; host-specific unit overrides are not
needed. The default backup user and group are `vaultwarden`. A custom identity
must be able to read the live vault and write the destination.

## Initial access and credentials

Open `/admin` and use the token from:

```bash
sudo cat /run/secrets/vaultwarden/adminToken
```

This token is not a vault user password. Because signups are disabled, use the
admin area to invite the initial user. Inspect `vaultwarden.service`.

## Recovery and service tests

The general Borg policy stops Vaultwarden and captures its authoritative native
state directory. Its default is `/var/lib/bitwarden_rs` for state versions before
24.11 and `/var/lib/vaultwarden` for newer hosts. Policy follows the effective
native `DATA_FOLDER` setting, including its camel-case alias and null fallback.
Custom directories still require the native service's permissions and mounts;
setting a path alone does not provision an arbitrary directory.

For the default SQLite/key profile, restore requires `db.sqlite3` and
`rsa_key.pem` before stopping the application. Explicit database/key overrides
are not mistaken for those default files. External SQL and opaque runtime
EnvironmentFile overrides need separate recovery ownership and remain outside
the verified profile. Optional native snapshots require local `db.sqlite3` and
attachment/send/key paths below the data directory; configuring external SQL
without enabling native snapshots remains supported.

The maintained x86_64 fixture checks native startup/readiness and one shipped
Borg backup/restore with an independent test-owned continuity marker. It erases
the declared application root and checks the marker after final readiness.
Business workflows, repeated lifecycle and failure matrices are outside this
smoke fixture. The combined startup/recovery check passed in 40.70 seconds.
Configuration is checked independently on x86_64 and aarch64.

The fixture selects `system.stateVersion = "23.11"` for its native SQLite
root and uses a runtime SOPS admin token. Browser clients, encrypted
items/attachments and snapshot failure loops are outside the maintained smoke. Modern default paths retain configuration
coverage.
