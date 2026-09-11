# MongoDB

MongoDB is a document database. Nixstead runs the native MongoDB service with
authentication enabled and provides the initial root password through a
service-readable SOPS file.

## Enable and configure

```nix
nixstead.services.dev.mongodb = {
  enable = true;
  port = 27017;
};
```

Generate the `devdb` branch before activation. This is a TCP database endpoint,
not a web UI.

## Initial credentials

The initial administrator username is `root`; read the password on the host:

```bash
sudo cat /run/secrets/devdb/mongodb/rootPassword
```

Use the `admin` authentication database when connecting. Inspect
`mongodb.service` with `systemctl` and `journalctl`.

The initial password is used when creating the first `root` account. Replacing
the SOPS value restarts MongoDB but does not change an existing database user's
password. Rotate that account through MongoDB's authenticated user-management
API and keep the encrypted credential source aligned. If the native completion
marker is missing, initialization authenticates the existing root account with
that source and preserves its password. A mismatched source refuses startup
without changing existing accounts. Reconcile the encrypted source with the
current account before retrying. Native `initialScript` runs once for a newly
created database.

The wrapper's initialization clients use the configured port. Passwords are read
inside the client from the runtime file, including for `initialScript`; they are
not interpolated into JavaScript source or supplied as process arguments. A
missing initial password file refuses new-database initialization before creating
the database directory. Initialization has a bounded readiness wait and cleans
up its temporary server on failure.
The temporary loopback server also keeps authentication enabled: an empty
database uses MongoDB's native localhost exception to create its first account.

## State and recovery boundary

The standalone native WiredTiger profile owns `services.mongodb.dbpath` (the
pinned native default is `/var/db/mongodb`). The registry follows an override of
that path. Backup stops `mongodb.service` before staging its complete directory,
including documents, indexes, accounts and authentication state. Runtime SOPS
files are recovered from their separately retained encrypted source and age
identity. The archive does not rotate credentials or replace that source.

Restore requires populated `storage.bson`, `WiredTiger`, `WiredTiger.wt` and
`WiredTiger.turtle` files. Before changing a destination, a native preflight
rejects symlinks and special files, copies the snapshot into a private temporary
directory, starts the selected MongoDB package in a private network namespace,
waits for its listener and requires a clean shutdown. The native check can modify
only its copy. Failure to create that namespace also refuses recovery. This
checks standalone WiredTiger startup at the selected revision; it does not scan
every collection page or establish replica-set, sharded, encrypted-engine or
cross-version recovery compatibility.

## Dedicated checks

The fixtures select native MongoDB CE 8.2.12, custom port 23456 and a custom
database directory. The combined fixture starts MongoDB with a runtime-generated
root credential and writes one small exact marker document. The same VM then
creates one encrypted Borg backup, removes the complete database directory,
restores it through the shipped command and verifies readiness plus the same
marker. Account/role workflows, credential rotation, failure matrices,
restart/reboot, cluster profiles, exhaustive page integrity, ARM runtime and
cross-version upgrades remain outside these fast checks.

A single `service-mongodb-recovery` VM covers initial startup/readiness and
one clean backup/restore.
