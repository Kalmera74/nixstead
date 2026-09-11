# Seafile

Seafile provides file synchronization and sharing. Nixstead runs digest-pinned
Seafile, MariaDB, and Memcached containers and rewrites the generated service
URLs for HTTPS behind the managed reverse proxy.

## Enable and configure

```nix
nixstead.services.productivity.seafile = {
  enable = true;
  domain = "seafile.home.arpa";
  port = 8184;
  paths.dataDir = "/var/lib/seafile";
};
```

Generate database and administrator values with
`nixstead --host <host> credentials bootstrap seafile`. Image overrides are available
under `images.database`, `images.memcached`, and `images.application`.

## Initial credentials

```bash
sudo cat /run/secrets/seafile/adminEmail
sudo cat /run/secrets/seafile/adminPassword
```

Open `https://seafile.home.arpa`. Inspect `docker-seafile.service`,
`docker-seafile-db.service`, and `docker-seafile-memcached.service`.

## Combined recovery boundary

The application tree at `<dataDir>/data` and all three MariaDB databases
(`ccnet_db`, `seafile_db`, `seahub_db`) form one recovery unit. This includes
account and token records, library metadata, file blocks, commit/filesystem
objects, Seahub settings and generated credential/signing material. The raw
MariaDB volume at `<dataDir>/db` is reconstructed from logical SQL dumps.
Memcached is disposable and reconstructs its cached responses from restored
application state. This follows the [Seafile database and data recovery model](https://manual.seafile.com/13.0/administration/backup_recovery/).

Nixstead makes the root-owned data tree private (`0700`). The pinned container
writes its generated database password and Seahub secret into the configuration
directory beneath that root. Its expected `memcached` hostname is supplied as a
network alias for the dedicated cache container.

The managed HTTPS update waits for native bootstrap to finish and for Seahub to
answer its local API, with a bounded five-minute startup and health grace window
for the initial schema setup. When settings change, it allows graceful Seahub
shutdown a bounded retry window before starting the new process. The pinned
native stop script's one-second wait can expire before its workers have exited.

On an empty database volume, the three application dumps do not recreate SQL
accounts. Before the application starts, Nixstead reads the existing private
`seafile.conf`, recreates its missing application account with the native host
selector, and grants access to the three Seafile databases. SQL travels over
standard input; the database root password is read inside its container. An
existing account's password is preserved. This does not back up or replace
MariaDB's system database or promise arbitrary custom database/user layouts.

Preflight requires the three named database sections and the native dump
completion marker, plus required configuration files and the blocks, commits
and filesystem-object directories. It refuses missing recovery material before
stopping the live service or changing files. This checks the expected dump
structure, not arbitrary SQL semantics or every individual block inside an
otherwise present directory.

## Service smoke checks

The x86_64 fixtures load the exact pinned application, MariaDB and Memcached
images offline. The real managed nginx HTTPS endpoint
is checked against the CA generated inside the guest. Native bootstrap must
complete without an automatic application restart. Credentials are generated
inside the guest and encrypted before SOPS provisioning.

The smoke records the initial administrator token, hashes of the required native
configuration and one explicit state-file marker. Recovery creates an encrypted
Borg archive, erases both the application tree and raw MariaDB volume, and
restores all three application databases with the shared tree. The checks then
require clean readiness, the original administrator identity, configuration and
marker bytes. Memcached is reconstructed during service startup.

This is a startup and backup/restore check for the pinned community 11.0.13
profile. Library workflows, client synchronization, encrypted libraries, detailed
failure matrices, repeated lifecycle/reboot testing, external object storage,
clusters and cross-version upgrades are outside the maintained smoke contract.
ARM configuration evaluation does not establish ARM runtime support.

The maintained x86_64 startup and clean recovery smoke passed in 431.64 seconds.
It includes the offline image import and one empty application/MariaDB restore.
Configuration assertions passed on x86_64 and aarch64; this host has no ARM
builder, so ARM configuration derivations were evaluated without realization.
